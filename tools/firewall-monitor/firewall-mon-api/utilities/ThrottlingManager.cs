using System.Collections.Concurrent;
using System.Net;
using firewallmon.function;
using Microsoft.AspNetCore.Http;

namespace firewallmon.utilities;

internal sealed class RequestLog
{
    public List<DateTime> Requests { get; } = new();
    public bool IsRemoved { get; set; }
}

public class ThrottlingManager
{
    private const int DefaultMaxTrackedBuckets = 1000;
    private const string OverflowBucketKey = "__overflow__";

    private readonly int _throttlingIntervalMilliseconds;
    private readonly int _throttlingRequests;
    private readonly int _maxTrackedBuckets;
    private readonly Func<DateTime> _utcNowProvider;
    private readonly ConcurrentDictionary<string, RequestLog> _ipLogs = new(StringComparer.OrdinalIgnoreCase);
    private long _lastCleanupTicks;
    private int _cleanupInProgress;

    private bool IsThrottlingEnabled => _throttlingIntervalMilliseconds > 0 && _throttlingRequests > 0;

    internal int TrackedBucketCount => _ipLogs.Count;

    public ThrottlingManager(int throttlingIntervalMilliseconds, int throttlingRequests)
        : this(throttlingIntervalMilliseconds, throttlingRequests, null, DefaultMaxTrackedBuckets)
    {
    }

    internal ThrottlingManager(
        int throttlingIntervalMilliseconds,
        int throttlingRequests,
        Func<DateTime>? utcNowProvider,
        int maxTrackedBuckets = DefaultMaxTrackedBuckets)
    {
        _throttlingIntervalMilliseconds = throttlingIntervalMilliseconds;
        _throttlingRequests = throttlingRequests;
        _utcNowProvider = utcNowProvider ?? (() => DateTime.UtcNow);
        _maxTrackedBuckets = Math.Max(1, maxTrackedBuckets);
        _lastCleanupTicks = _utcNowProvider().Ticks;
    }

    public bool ImplementThrottling(HttpRequest req)
    {
        if (!IsThrottlingEnabled)
        {
            return false;
        }

        var now = _utcNowProvider();
        string bucketKey = ResolveClientIp(req);

        MaybePruneExpiredBuckets(now, forceIfOverCapacity: !_ipLogs.ContainsKey(bucketKey));

        if (!_ipLogs.ContainsKey(bucketKey) && _ipLogs.Count >= _maxTrackedBuckets)
        {
            bucketKey = OverflowBucketKey;
        }

        while (true)
        {
            var logEntry = _ipLogs.GetOrAdd(bucketKey, _ => new RequestLog());
            lock (logEntry)
            {
                if (logEntry.IsRemoved)
                {
                    continue;
                }

                logEntry.Requests.RemoveAll(t => (now - t).TotalMilliseconds > _throttlingIntervalMilliseconds);

                if (logEntry.Requests.Count >= _throttlingRequests)
                {
                    return true;
                }

                logEntry.Requests.Add(now);
                return false;
            }
        }
    }

    internal static string ResolveClientIp(HttpRequest req)
    {
        var remoteIp = req.HttpContext?.Connection?.RemoteIpAddress;
        if (remoteIp is not null)
        {
            remoteIp = remoteIp.IsIPv4MappedToIPv6 ? remoteIp.MapToIPv4() : remoteIp;
        }

        // Only trust forwarded proxy headers when the immediate peer is absent (in-memory host)
        // or is a private/loopback/link-local reverse proxy (such as Azure Static Web Apps).
        bool peerIsTrustedProxy = remoteIp is null || !Backend.IsPublicRoutableAddress(remoteIp);
        if (peerIsTrustedProxy)
        {
            if (TryExtractHeaderIp(req.Headers["X-Forwarded-For"].ToString(), out var forwardedIp))
            {
                return forwardedIp;
            }

            if (TryExtractHeaderIp(req.Headers["Client-IP"].ToString(), out var clientIp))
            {
                return clientIp;
            }
        }

        return remoteIp?.ToString() ?? "unknown";
    }

    private static bool TryExtractHeaderIp(string? headerValue, out string normalizedIp)
    {
        normalizedIp = string.Empty;
        if (string.IsNullOrWhiteSpace(headerValue))
        {
            return false;
        }

        var firstToken = headerValue.Split(',')[0].Trim();
        if (string.IsNullOrWhiteSpace(firstToken) || firstToken.Contains('%'))
        {
            return false;
        }

        if (IPAddress.TryParse(firstToken, out var directIp))
        {
            if (directIp.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork &&
                firstToken.Split('.').Length != 4)
            {
                return false;
            }

            normalizedIp = (directIp.IsIPv4MappedToIPv6 ? directIp.MapToIPv4() : directIp).ToString();
            return true;
        }

        if (IPEndPoint.TryParse(firstToken, out var endpoint))
        {
            if (endpoint.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
            {
                var hostPart = firstToken[..firstToken.LastIndexOf(':')];
                if (hostPart.Split('.').Length != 4)
                {
                    return false;
                }
            }

            var addr = endpoint.Address.IsIPv4MappedToIPv6 ? endpoint.Address.MapToIPv4() : endpoint.Address;
            normalizedIp = addr.ToString();
            return true;
        }

        return false;
    }

    private void MaybePruneExpiredBuckets(DateTime now, bool forceIfOverCapacity)
    {
        var periodicSweepMs = Math.Max(_throttlingIntervalMilliseconds, 60_000);
        var minOverCapacityCooldownMs = Math.Min(_throttlingIntervalMilliseconds, 1_000);
        var lastTicks = Interlocked.Read(ref _lastCleanupTicks);
        var elapsedMs = TimeSpan.FromTicks(now.Ticks - lastTicks).TotalMilliseconds;

        bool duePeriodic = elapsedMs > periodicSweepMs;
        bool dueCapacity = forceIfOverCapacity && _ipLogs.Count >= _maxTrackedBuckets && elapsedMs >= minOverCapacityCooldownMs;

        if (!duePeriodic && !dueCapacity)
        {
            return;
        }

        if (Interlocked.CompareExchange(ref _cleanupInProgress, 1, 0) != 0)
        {
            return;
        }

        try
        {
            Interlocked.Exchange(ref _lastCleanupTicks, now.Ticks);
            foreach (var kvp in _ipLogs)
            {
                lock (kvp.Value)
                {
                    kvp.Value.Requests.RemoveAll(t => (now - t).TotalMilliseconds > _throttlingIntervalMilliseconds);
                    if (kvp.Value.Requests.Count == 0)
                    {
                        kvp.Value.IsRemoved = true;
                        _ipLogs.TryRemove(kvp);
                    }
                }
            }
        }
        finally
        {
            Interlocked.Exchange(ref _cleanupInProgress, 0);
        }
    }
}