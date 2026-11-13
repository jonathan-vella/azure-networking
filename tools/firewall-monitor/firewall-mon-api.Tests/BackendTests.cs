using System.Net;
using System.Text;
using System.Text.Json;
using firewallmon.function;
using firewallmon.utilities;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace firewallmon.tests;

public class BackendTests
{
    [Theory]
    [InlineData("")]
    [InlineData("not-an-ip")]
    [InlineData("999.999.999.999")]
    [InlineData("2130706433")]
    [InlineData("127.1")]
    [InlineData("127.0.0.1")]
    [InlineData("0.0.0.0")]
    [InlineData("10.1.2.3")]
    [InlineData("172.16.0.1")]
    [InlineData("172.31.255.254")]
    [InlineData("192.168.1.1")]
    [InlineData("169.254.169.254")]
    [InlineData("100.64.12.34")]
    [InlineData("192.0.2.10")]
    [InlineData("198.51.100.20")]
    [InlineData("203.0.113.30")]
    [InlineData("224.0.0.1")]
    [InlineData("255.255.255.255")]
    [InlineData("::1")]
    [InlineData("::")]
    [InlineData("fe80::1")]
    [InlineData("fe80::1%eth0")]
    [InlineData("fec0::1")]
    [InlineData("fc00::1")]
    [InlineData("fd12:3456:789a::1")]
    [InlineData("2001:db8::1")]
    [InlineData("ff02::1")]
    [InlineData("::ffff:10.1.2.3")]
    [InlineData("::ffff:127.0.0.1")]
    [InlineData("::10.1.2.3")]
    [InlineData("::127.0.0.1")]
    [InlineData("64:ff9b::10.1.2.3")]
    [InlineData("64:ff9b:1::1")]
    public async Task RunIpAsync_ShortCircuitsInvalidAndNonPublicAddressesWithoutHttpCall(string candidateIp)
    {
        var handler = new RecordingHttpMessageHandler(_ =>
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("""{"countryRegion":{"isoCode":"US"}}""", Encoding.UTF8, "application/json")
            });

        var backend = CreateBackend(handler, ipApiKey: "secret-maps-key");
        var req = new DefaultHttpContext().Request;

        var actionResult = await backend.RunIpAsync(req, candidateIp);

        var ok = Assert.IsType<OkObjectResult>(actionResult);
        Assert.Equal("zz", ok.Value);
        Assert.Equal(0, handler.CallCount);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("unknown")]
    [InlineData("UNKNOWN")]
    public async Task RunIpAsync_ReturnsZzWithoutHttpCall_WhenApiKeyMissingOrPlaceholder(string? apiKey)
    {
        var handler = new RecordingHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.OK));
        var backend = CreateBackend(handler, ipApiKey: apiKey);

        var actionResult = await backend.RunIpAsync(new DefaultHttpContext().Request, "8.8.8.8");

        var ok = Assert.IsType<OkObjectResult>(actionResult);
        Assert.Equal("zz", ok.Value);
        Assert.Equal(0, handler.CallCount);
    }

    [Fact]
    public async Task RunIpAsync_SendsSubscriptionKeyHeaderOnly_AndReturnsLowercaseIsoCode()
    {
        HttpRequestMessage? capturedRequest = null;
        var handler = new RecordingHttpMessageHandler(req =>
        {
            capturedRequest = req;
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("""{"countryRegion":{"isoCode":"IT"},"ipAddress":"8.8.8.8"}""", Encoding.UTF8, "application/json")
            };
        });

        const string mapsKey = "super-secret-azure-maps-key";
        var backend = CreateBackend(handler, ipApiKey: mapsKey);

        var actionResult = await backend.RunIpAsync(new DefaultHttpContext().Request, "8.8.8.8");

        var ok = Assert.IsType<OkObjectResult>(actionResult);
        Assert.Equal("it", ok.Value);
        Assert.Equal(1, handler.CallCount);
        Assert.NotNull(capturedRequest);
        Assert.Equal("https://atlas.microsoft.com/geolocation/ip/json?api-version=1.0&ip=8.8.8.8", capturedRequest!.RequestUri!.ToString());
        Assert.DoesNotContain("subscription-key", capturedRequest.RequestUri.Query, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(mapsKey, capturedRequest.RequestUri.ToString(), StringComparison.Ordinal);
        Assert.True(capturedRequest.Headers.TryGetValues("subscription-key", out var headerValues));
        Assert.Equal(mapsKey, Assert.Single(headerValues));
        Assert.False(capturedRequest.Headers.Contains("Ocp-Apim-Subscription-Key"));
    }

    [Theory]
    [InlineData("""{"countryRegion":null,"ipAddress":"8.8.8.8"}""")]
    [InlineData("""{"countryRegion":{"isoCode":null},"ipAddress":"8.8.8.8"}""")]
    [InlineData("""{}""")]
    public async Task RunIpAsync_SafelyReturnsZz_WhenCountryRegionOrIsoCodeIsNull(string payload)
    {
        var handler = new RecordingHttpMessageHandler(_ =>
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(payload, Encoding.UTF8, "application/json")
            });

        var backend = CreateBackend(handler, ipApiKey: "valid-maps-key");

        var actionResult = await backend.RunIpAsync(new DefaultHttpContext().Request, "8.8.8.8");

        var ok = Assert.IsType<OkObjectResult>(actionResult);
        Assert.Equal("zz", ok.Value);
        Assert.Equal(1, handler.CallCount);
    }

    [Theory]
    [InlineData("applicationinsights_connection_string", "InstrumentationKey=00000000-0000-0000-0000-000000000000")]
    [InlineData("builddate", "2026-11-13T00:00:00Z")]
    [InlineData("BuildDate", "2026-11-13T00:00:00Z")]
    [InlineData("local_queuelength", "100000")]
    public void RunSettings_AllowsConfiguredSpaAttributesCaseInsensitively(string attribute, string expected)
    {
        var env = new Dictionary<string, string?>(StringComparer.Ordinal)
        {
            ["spa_applicationinsights_connection_string"] = "InstrumentationKey=00000000-0000-0000-0000-000000000000",
            ["spa_builddate"] = "2026-11-13T00:00:00Z",
            ["spa_local_queuelength"] = "100000"
        };

        var backend = CreateBackend(
            new RecordingHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.OK)),
            envReader: key => env.GetValueOrDefault(key));

        var result = backend.RunSettings(new DefaultHttpContext().Request, attribute);

        var ok = Assert.IsType<OkObjectResult>(result);
        Assert.Equal(expected, ok.Value);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("aoai_api_key")]
    [InlineData("ip_api_key")]
    [InlineData("PATH")]
    [InlineData("AZURE_CLIENT_SECRET")]
    public void RunSettings_RejectsAttributesOutsideAllowlist(string attribute)
    {
        bool envReaderCalled = false;
        var backend = CreateBackend(
            new RecordingHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.OK)),
            envReader: _ =>
            {
                envReaderCalled = true;
                return "leaked-secret";
            });

        var result = backend.RunSettings(new DefaultHttpContext().Request, attribute);

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.False(envReaderCalled);
    }

    [Fact]
    public void BuildFilterSystemPrompt_ContainsOnlyValidLowercaseJsonExamples()
    {
        string context = SearchParamsUtility.Encode(SearchParamsUtility.CreateDefaultParams());
        string systemPrompt = Backend.BuildFilterSystemPrompt(context);

        Assert.DoesNotContain("\"lastminutes\": O", systemPrompt, StringComparison.Ordinal);

        var exampleLines = systemPrompt
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Where(line => line.StartsWith("answer:", StringComparison.Ordinal))
            .Select(line => line["answer:".Length..].Trim())
            .ToList();

        Assert.Equal(5, exampleLines.Count);

        foreach (var jsonExample in exampleLines)
        {
            using var doc = JsonDocument.Parse(jsonExample);
            Assert.Equal(JsonValueKind.Object, doc.RootElement.ValueKind);
            Assert.Equal(JsonValueKind.Number, doc.RootElement.GetProperty("lastminutes").ValueKind);

            foreach (var prop in doc.RootElement.EnumerateObject())
            {
                Assert.Equal(prop.Name.ToLowerInvariant(), prop.Name);
            }
        }
    }

    [Fact]
    public async Task RunChatAsync_UsesSeparateFilterAndSummaryPrompts_WithoutDollarInterpolationBug()
    {
        var calls = new List<(string SystemPrompt, string UserMessage)>();
        const string sampleFilterJson = """{"fulltext":[],"startdate":"","enddate":"","lastminutes":5,"category":["azfwnetworkrule"],"protocol":["tcp"],"source":[],"target":[],"action":["deny"],"policy":[],"moreinfo":[]}""";

        var backend = new Backend(
            NullLogger<Backend>.Instance,
            new StubHttpClientFactory(new RecordingHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.OK))),
            llmThrottlingManager: new ThrottlingManager(0, 0),
            ipThrottlingManager: new ThrottlingManager(0, 0),
            chatCompletionOverride: (sys, usr, _) =>
            {
                calls.Add((sys, usr));
                return Task.FromResult(calls.Count == 1
                    ? sampleFilterJson
                    : "I am currently showing denied TCP azfwnetworkrule events from the last 5 minutes.");
            });

        var httpContext = new DefaultHttpContext();
        httpContext.Request.QueryString = new QueryString(
            $"?message={Uri.EscapeDataString("show denied tcp network rules from last 5 minutes")}&context={Uri.EscapeDataString("{}")}");

        var actionResult = await backend.RunChatAsync(httpContext.Request);

        var ok = Assert.IsType<OkObjectResult>(actionResult);
        string serialized = JsonSerializer.Serialize(ok.Value);
        using var responseDoc = JsonDocument.Parse(serialized);
        Assert.Equal(sampleFilterJson, responseDoc.RootElement.GetProperty("json").GetString());
        Assert.StartsWith("I am currently showing", responseDoc.RootElement.GetProperty("message").GetString());

        Assert.Equal(2, calls.Count);
        Assert.Contains("your answer must be a valid JSON message", calls[0].SystemPrompt, StringComparison.Ordinal);
        Assert.Equal(Backend.FilterSummarySystemPrompt, calls[1].SystemPrompt);
        Assert.DoesNotContain("your answer must be a valid JSON message", calls[1].SystemPrompt, StringComparison.Ordinal);
        Assert.Contains(sampleFilterJson, calls[1].UserMessage, StringComparison.Ordinal);
        Assert.DoesNotContain("${", calls[1].UserMessage, StringComparison.Ordinal);
    }

    [Fact]
    public void GetOrCreateChatClient_ValidatesConfigAndReusesUnderlyingOpenAiClient()
    {
        var unconfigured = new Backend(
            NullLogger<Backend>.Instance,
            new StubHttpClientFactory(new RecordingHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.OK))),
            openAiEndpoint: "unknown",
            openAiDeployment: "gpt4o",
            openAiKey: "unknown");

        Assert.Throws<InvalidOperationException>(() => unconfigured.GetOrCreateChatClient());

        var configuredA = new Backend(
            NullLogger<Backend>.Instance,
            new StubHttpClientFactory(new RecordingHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.OK))),
            openAiEndpoint: "https://example-aoai.openai.azure.com/",
            openAiDeployment: "gpt4o",
            openAiKey: "test-aoai-key");

        var configuredB = new Backend(
            NullLogger<Backend>.Instance,
            new StubHttpClientFactory(new RecordingHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.OK))),
            openAiEndpoint: "https://example-aoai.openai.azure.com/",
            openAiDeployment: "gpt4o",
            openAiKey: "test-aoai-key");

        Assert.NotNull(configuredA.GetOrCreateChatClient());
        Assert.NotNull(configuredB.GetOrCreateChatClient());
    }

    private static Backend CreateBackend(
        HttpMessageHandler handler,
        string? ipApiKey = "test-key",
        Func<string, string?>? envReader = null)
    {
        return new Backend(
            NullLogger<Backend>.Instance,
            new StubHttpClientFactory(handler),
            llmThrottlingManager: new ThrottlingManager(0, 0),
            ipThrottlingManager: new ThrottlingManager(0, 0),
            ipApiKey: ipApiKey,
            environmentVariableReader: envReader);
    }

    private sealed class StubHttpClientFactory(HttpMessageHandler handler) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new(handler, disposeHandler: false);
    }

    private sealed class RecordingHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> responder) : HttpMessageHandler
    {
        private int _callCount;
        public int CallCount => _callCount;

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref _callCount);
            return Task.FromResult(responder(request));
        }
    }
}
