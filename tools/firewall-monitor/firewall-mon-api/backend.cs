using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using Azure;
using Azure.AI.OpenAI;
using firewallmon.models;
using firewallmon.utilities;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using OpenAI.Chat;

namespace firewallmon.function;

public class Backend
{
    private static readonly HashSet<string> AllowedSettingsAttributes = new(StringComparer.OrdinalIgnoreCase)
    {
        "applicationinsights_connection_string",
        "builddate",
        "local_queuelength"
    };

    private static readonly ThrottlingManager DefaultLlmThrottlingManager = new(
        int.TryParse(Environment.GetEnvironmentVariable("llm_throttling_window_milliseconds"), out var llmInterval) ? llmInterval : 0,
        int.TryParse(Environment.GetEnvironmentVariable("llm_throttling_calls"), out var llmRequests) ? llmRequests : 0
    );

    private static readonly ThrottlingManager DefaultIpThrottlingManager = new(
        int.TryParse(Environment.GetEnvironmentVariable("ip_throttling_window_milliseconds"), out var ipInterval) ? ipInterval : 0,
        int.TryParse(Environment.GetEnvironmentVariable("ip_throttling_calls"), out var ipRequests) ? ipRequests : 0
    );

    private sealed record CachedOpenAiClient(string Endpoint, string Key, AzureOpenAIClient Client);

    private static readonly object OpenAiClientLock = new();
    private static CachedOpenAiClient? _cachedOpenAiClient;

    internal const string FilterSummarySystemPrompt =
        "You summarize active Azure Firewall log filters for a web console user in one concise plain-English sentence. " +
        "Omit empty arrays, empty strings, and lastminutes when it is 0. " +
        "Do not return JSON, markdown code fences, or HTML tags. " +
        "Always start your response with 'I am currently showing ...'.";

    private readonly ILogger<Backend> _logger;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ThrottlingManager _llmThrottlingManager;
    private readonly ThrottlingManager _ipThrottlingManager;
    private readonly string _ipApiKey;
    private readonly string _openAiEndpoint;
    private readonly string _openAiDeployment;
    private readonly string _openAiKey;
    private readonly Func<string, string?> _environmentVariableReader;
    private readonly Func<string, string, CancellationToken, Task<string>>? _chatCompletionOverride;

    [ActivatorUtilitiesConstructor]
    public Backend(ILogger<Backend> logger, IHttpClientFactory httpClientFactory)
        : this(
            logger,
            httpClientFactory,
            DefaultLlmThrottlingManager,
            DefaultIpThrottlingManager,
            Environment.GetEnvironmentVariable("ip_api_key"),
            Environment.GetEnvironmentVariable("aoai_endpoint"),
            Environment.GetEnvironmentVariable("aoai_deployment"),
            Environment.GetEnvironmentVariable("aoai_api_key"),
            Environment.GetEnvironmentVariable,
            null)
    {
    }

    internal Backend(
        ILogger<Backend> logger,
        IHttpClientFactory httpClientFactory,
        ThrottlingManager? llmThrottlingManager = null,
        ThrottlingManager? ipThrottlingManager = null,
        string? ipApiKey = null,
        string? openAiEndpoint = null,
        string? openAiDeployment = null,
        string? openAiKey = null,
        Func<string, string?>? environmentVariableReader = null,
        Func<string, string, CancellationToken, Task<string>>? chatCompletionOverride = null)
    {
        _logger = logger;
        _httpClientFactory = httpClientFactory;
        _llmThrottlingManager = llmThrottlingManager ?? DefaultLlmThrottlingManager;
        _ipThrottlingManager = ipThrottlingManager ?? DefaultIpThrottlingManager;
        _ipApiKey = ipApiKey ?? "unknown";
        _openAiEndpoint = openAiEndpoint ?? "unknown";
        _openAiDeployment = openAiDeployment ?? "unknown";
        _openAiKey = openAiKey ?? "unknown";
        _environmentVariableReader = environmentVariableReader ?? Environment.GetEnvironmentVariable;
        _chatCompletionOverride = chatCompletionOverride;
    }

    [Function("helloWorld")]
    public IActionResult Run([HttpTrigger(AuthorizationLevel.Anonymous, "get", "post")] HttpRequest req)
    {
        if (_llmThrottlingManager.ImplementThrottling(req))
        {
            return new ContentResult
            {
                StatusCode = StatusCodes.Status429TooManyRequests,
                Content = "Too many requests. Please try again later."
            };
        }

        return new OkObjectResult("Hello from the other side... of the endpoint.");
    }

    [Function("settings")]
    public IActionResult RunSettings([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "settings/{attribute}")] HttpRequest req, string attribute)
    {
        if (string.IsNullOrWhiteSpace(attribute) || !AllowedSettingsAttributes.Contains(attribute))
        {
            return new BadRequestObjectResult("Unsupported setting attribute.");
        }

        string canonicalName = $"spa_{attribute.ToLowerInvariant()}";
        string? attributeValue = _environmentVariableReader(canonicalName) ?? _environmentVariableReader($"spa_{attribute}");
        return new OkObjectResult(attributeValue ?? "not set");
    }

    [Function("ip")]
    public async Task<IActionResult> RunIpAsync([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "ip/{ipAddress}")] HttpRequest req, string ipAddress)
    {
        if (!TryParsePublicRoutableIp(ipAddress, out var parsedIp))
        {
            return new OkObjectResult("zz");
        }

        if (!IsConfiguredSecret(_ipApiKey))
        {
            return new OkObjectResult("zz");
        }

        if (_ipThrottlingManager.ImplementThrottling(req))
        {
            return new ContentResult
            {
                StatusCode = StatusCodes.Status429TooManyRequests,
                Content = "Too many requests. Please try again later."
            };
        }

        var requestUri = $"https://atlas.microsoft.com/geolocation/ip/json?api-version=1.0&ip={Uri.EscapeDataString(parsedIp.ToString())}";
        var country = "zz";

        try
        {
            var httpClient = _httpClientFactory.CreateClient();
            using var request = new HttpRequestMessage(HttpMethod.Get, requestUri);
            request.Headers.TryAddWithoutValidation("subscription-key", _ipApiKey);

            var cancellationToken = req.HttpContext?.RequestAborted ?? CancellationToken.None;
            using var response = await httpClient.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();

            var json = await response.Content.ReadAsStringAsync(cancellationToken);
            var apiResponse = JsonSerializer.Deserialize<AzureAPIResponse>(json);
            var isoCode = apiResponse?.countryRegion?.isoCode?.Trim().ToLowerInvariant();
            if (!string.IsNullOrEmpty(isoCode))
            {
                country = isoCode;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error resolving geolocation for IP address.");
        }

        return new OkObjectResult(country);
    }

    [Function("chat")]
    public async Task<IActionResult> RunChatAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "chat")] HttpRequest req)
    {
        if (_llmThrottlingManager.ImplementThrottling(req))
        {
            return new ContentResult
            {
                StatusCode = StatusCodes.Status429TooManyRequests,
                Content = "Too many requests. Please try again later."
            };
        }

        try
        {
            string? message = req.Query["message"];
            string? contextInput = req.Query["context"];

            if (string.IsNullOrEmpty(message))
            {
                return new BadRequestObjectResult("Please provide a message parameter");
            }

            if (string.IsNullOrEmpty(contextInput))
            {
                return new BadRequestObjectResult("Please provide a context input parameter");
            }

            var searchParams = SearchParamsUtility.Decode(contextInput);
            string context = SearchParamsUtility.Encode(searchParams);
            var cancellationToken = req.HttpContext?.RequestAborted ?? CancellationToken.None;

            var filterJson = await CompleteChatAsync(
                BuildFilterSystemPrompt(context),
                message,
                cancellationToken);

            string summaryMessage;
            if (filterJson.TrimStart().StartsWith("{", StringComparison.Ordinal))
            {
                var summaryPrompt =
                    $@"Convert the following JSON message into human-readable text.
Omit empty fields and zero lastminutes.
Start the answer with 'I am currently showing ...':
{filterJson}";
                summaryMessage = await CompleteChatAsync(
                    FilterSummarySystemPrompt,
                    summaryPrompt,
                    cancellationToken);
            }
            else
            {
                summaryMessage = filterJson;
            }

            return new OkObjectResult(new
            {
                timestamp = DateTime.UtcNow.ToString("o"),
                json = filterJson,
                message = summaryMessage
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing chat request.");
            return new ObjectResult("An error occurred while processing your request.")
            {
                StatusCode = StatusCodes.Status500InternalServerError
            };
        }
    }

    internal static bool TryParsePublicRoutableIp(string? ipAddress, out IPAddress normalizedIp)
    {
        normalizedIp = IPAddress.None;
        if (string.IsNullOrWhiteSpace(ipAddress))
        {
            return false;
        }

        var trimmed = ipAddress.Trim();
        if (trimmed.Contains('%'))
        {
            return false;
        }

        if (!IPAddress.TryParse(trimmed, out var parsedIp))
        {
            return false;
        }

        if (parsedIp.AddressFamily == AddressFamily.InterNetwork && trimmed.Split('.').Length != 4)
        {
            return false;
        }

        if (parsedIp.IsIPv4MappedToIPv6)
        {
            parsedIp = parsedIp.MapToIPv4();
        }

        if (!IsPublicRoutableAddress(parsedIp))
        {
            return false;
        }

        normalizedIp = parsedIp;
        return true;
    }

    internal static bool IsPublicRoutableAddress(IPAddress ip)
    {
        if (ip.IsIPv4MappedToIPv6)
        {
            ip = ip.MapToIPv4();
        }

        if (IPAddress.IsLoopback(ip) || ip.Equals(IPAddress.Any) || ip.Equals(IPAddress.IPv6Any))
        {
            return false;
        }

        if (ip.AddressFamily == AddressFamily.InterNetwork)
        {
            var b = ip.GetAddressBytes();

            // 0.0.0.0/8 ("this" network / unspecified)
            if (b[0] == 0) return false;
            // 10.0.0.0/8 (RFC 1918 private)
            if (b[0] == 10) return false;
            // 100.64.0.0/10 (RFC 6598 CGNAT)
            if (b[0] == 100 && (b[1] & 0xC0) == 64) return false;
            // 127.0.0.0/8 (Loopback)
            if (b[0] == 127) return false;
            // 169.254.0.0/16 (RFC 3927 link-local)
            if (b[0] == 169 && b[1] == 254) return false;
            // 172.16.0.0/12 (RFC 1918 private)
            if (b[0] == 172 && (b[1] & 0xF0) == 16) return false;
            // 192.0.0.0/24 (RFC 6890 IETF protocol assignments)
            if (b[0] == 192 && b[1] == 0 && b[2] == 0) return false;
            // 192.0.2.0/24 (RFC 5737 TEST-NET-1 documentation)
            if (b[0] == 192 && b[1] == 0 && b[2] == 2) return false;
            // 192.88.99.0/24 (RFC 7526 deprecated 6to4 relay anycast)
            if (b[0] == 192 && b[1] == 88 && b[2] == 99) return false;
            // 192.168.0.0/16 (RFC 1918 private)
            if (b[0] == 192 && b[1] == 168) return false;
            // 198.18.0.0/15 (RFC 2544 benchmarking)
            if (b[0] == 198 && (b[1] & 0xFE) == 18) return false;
            // 198.51.100.0/24 (RFC 5737 TEST-NET-2 documentation)
            if (b[0] == 198 && b[1] == 51 && b[2] == 100) return false;
            // 203.0.113.0/24 (RFC 5737 TEST-NET-3 documentation)
            if (b[0] == 203 && b[1] == 0 && b[2] == 113) return false;
            // 224.0.0.0/4 (Multicast) and 240.0.0.0/4 (Reserved / Broadcast)
            if (b[0] >= 224) return false;

            return true;
        }

        if (ip.AddressFamily == AddressFamily.InterNetworkV6)
        {
            if (ip.IsIPv6LinkLocal || ip.IsIPv6SiteLocal || ip.IsIPv6Multicast || ip.IsIPv6Teredo)
            {
                return false;
            }

            var b = ip.GetAddressBytes();

            // Only IANA Global Unicast 2000::/3 is publicly routable on the internet
            // (automatically excludes ::/96 IPv4-compatible, 64:ff9b::/96 & 64:ff9b:1::/48 NAT64,
            // 100::/64 discard, fc00::/7 ULA, fe80::/10 link-local, fec0::/10 site-local, ff00::/8 multicast)
            if ((b[0] & 0xE0) != 0x20)
            {
                return false;
            }

            // 2001:0000::/23 (RFC 6890 IETF protocol assignments, including Teredo 2001::/32 and BMWG 2001:2::/48)
            if (b[0] == 0x20 && b[1] == 0x01 && (b[2] & 0xFE) == 0x00)
            {
                return false;
            }

            // 2001:db8::/32 (RFC 3849 Documentation)
            if (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0D && b[3] == 0xB8)
            {
                return false;
            }

            // 2002::/16 (6to4) - validate embedded IPv4 address
            if (b[0] == 0x20 && b[1] == 0x02)
            {
                var embeddedIpv4 = new IPAddress(new[] { b[2], b[3], b[4], b[5] });
                return IsPublicRoutableAddress(embeddedIpv4);
            }

            return true;
        }

        return false;
    }

    private static bool IsConfiguredSecret(string? value) =>
        !string.IsNullOrWhiteSpace(value) &&
        !string.Equals(value.Trim(), "unknown", StringComparison.OrdinalIgnoreCase);

    internal static string BuildFilterSystemPrompt(string context) => $@"You are an AI assistant that 
converts user requests to a JSON (not JSON5) message to use as filters for a web console that filters flow logs coming from an Azure Firewall. 

Allowed fields are: fulltext, startdate, enddate, lastminutes, category, protocol, source, target, action, policy, moreinfo.
All values must be converted to lowercase.

startdate and enddate are strings in the format 'HH:mm' or 'HH:mm:ss', representing the local time of the day, no gmt. 

lastminutes is a number of minutes in the past to show starting from the current time.
lastminutes and startdate/enddate are mutually exclusive, if both are present, lastminutes is used.
lastminutes = 0 means no lastminutes filter.

the request can be generic, search the text on all fields, or specific to one or more fields.

by default, the request adds parameters to the current json message, but it is also possible to replace the JSON message with a new one.

if you want to show how to use this agent, just show sample requests and not the JSON output, and begins the sentence with 'here some examples query you can use:'

some examples:
answer:{{""fulltext"":[],""startdate"":"""",""enddate"":"""",""lastminutes"": 12,""category"":[],""protocol"":[],""source"":[],""target"":[],""action"":[],""policy"":[],""moreinfo"":[]}}

user: search pippo pluto paperino
answer:{{""fulltext"":[""pippo"",""pluto"",""paperino""],""startdate"":"""",""enddate"":"""",""lastminutes"": 0,""category"":[],""protocol"":[],""source"":[],""target"":[],""action"":[],""policy"":[],""moreinfo"":[]}}

user: filter rows with category containing ""NetworkRule""
answer:{{""fulltext"":[],""startdate"":"""",""enddate"":"""",""lastminutes"": 0,""category"":[""networkrule""],""protocol"":[],""source"":[],""target"":[],""action"":[],""policy"":[],""moreinfo"":[]}}

user: filter event between 10:30 and 10:45
answer:{{""fulltext"":[],""startdate"":""10:30"",""enddate"":""10:45"",""lastminutes"": 0,""category"":[],""protocol"":[],""source"":[],""target"":[],""action"":[],""policy"":[],""moreinfo"":[]}}

user: clear all filters
answer:{{""fulltext"":[],""startdate"":"""",""enddate"":"""",""lastminutes"": 0,""category"":[],""protocol"":[],""source"":[],""target"":[],""action"":[],""policy"":[],""moreinfo"":[]}}

current json message is: {context}

your answer must be a valid JSON message, with all fields in lowercase, and no comments or explanations.
";

    internal ChatClient GetOrCreateChatClient()
    {
        if (!IsConfiguredSecret(_openAiKey) ||
            !IsConfiguredSecret(_openAiEndpoint) ||
            !IsConfiguredSecret(_openAiDeployment) ||
            !Uri.TryCreate(_openAiEndpoint, UriKind.Absolute, out var endpointUri))
        {
            _logger.LogError("OpenAI API configuration is missing or invalid.");
            throw new InvalidOperationException("OpenAI API is not properly configured");
        }

        var snapshot = Volatile.Read(ref _cachedOpenAiClient);
        if (snapshot is null ||
            !string.Equals(snapshot.Endpoint, _openAiEndpoint, StringComparison.Ordinal) ||
            !string.Equals(snapshot.Key, _openAiKey, StringComparison.Ordinal))
        {
            lock (OpenAiClientLock)
            {
                snapshot = _cachedOpenAiClient;
                if (snapshot is null ||
                    !string.Equals(snapshot.Endpoint, _openAiEndpoint, StringComparison.Ordinal) ||
                    !string.Equals(snapshot.Key, _openAiKey, StringComparison.Ordinal))
                {
                    var created = new AzureOpenAIClient(endpointUri, new AzureKeyCredential(_openAiKey));
                    snapshot = new CachedOpenAiClient(_openAiEndpoint, _openAiKey, created);
                    Volatile.Write(ref _cachedOpenAiClient, snapshot);
                }
            }
        }

        return snapshot.Client.GetChatClient(_openAiDeployment);
    }

    private async Task<string> CompleteChatAsync(
        string systemPrompt,
        string userMessage,
        CancellationToken cancellationToken)
    {
        if (_chatCompletionOverride is not null)
        {
            return await _chatCompletionOverride(systemPrompt, userMessage, cancellationToken);
        }

        try
        {
            ChatClient chatClient = GetOrCreateChatClient();

            var requestOptions = new ChatCompletionOptions
            {
                MaxOutputTokenCount = 4096,
                Temperature = 1.0f,
                TopP = 1.0f,
            };

            List<ChatMessage> messages =
            [
                new SystemChatMessage(systemPrompt),
                new UserChatMessage(userMessage),
            ];

            var response = await chatClient.CompleteChatAsync(messages, requestOptions, cancellationToken);
            if (response.Value.Content.Count == 0 || string.IsNullOrEmpty(response.Value.Content[0].Text))
            {
                throw new InvalidOperationException("OpenAI API returned an empty completion.");
            }

            return response.Value.Content[0].Text;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error calling OpenAI API.");
            throw;
        }
    }
}