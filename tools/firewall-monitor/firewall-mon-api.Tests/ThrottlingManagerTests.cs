using System.Net;
using firewallmon.utilities;
using Microsoft.AspNetCore.Http;
using Xunit;

namespace firewallmon.tests;

public class ThrottlingManagerTests
{
    [Fact]
    public void ImplementThrottling_EnforcesWindowAndRecoversAfterExpiration()
    {
        var now = new DateTime(2026, 11, 13, 12, 0, 0, DateTimeKind.Utc);
        var manager = new ThrottlingManager(1000, 2, () => now);
        var request = CreateRequest(remoteIp: "203.0.113.10");

        Assert.False(manager.ImplementThrottling(request));
        now = now.AddMilliseconds(400);
        Assert.False(manager.ImplementThrottling(request));
        now = now.AddMilliseconds(100);
        Assert.True(manager.ImplementThrottling(request));

        // Advance past the 1000ms window of the first request
        now = now.AddMilliseconds(600);
        Assert.False(manager.ImplementThrottling(request));
    }

    [Fact]
    public void ImplementThrottling_IsolatesUsersBehindReverseProxyViaXForwardedFor()
    {
        var now = new DateTime(2026, 11, 13, 12, 0, 0, DateTimeKind.Utc);
        var manager = new ThrottlingManager(60_000, 1, () => now);

        // Both requests arrive from the same SWA reverse-proxy RemoteIpAddress
        var userAFirstPort = CreateRequest(remoteIp: "10.0.0.5", xForwardedFor: "198.51.100.10:51234, 10.0.0.5");
        var userASecondPort = CreateRequest(remoteIp: "10.0.0.5", xForwardedFor: "198.51.100.10:59999, 10.0.0.5");
        var userB = CreateRequest(remoteIp: "10.0.0.5", xForwardedFor: "198.51.100.20, 10.0.0.5");

        Assert.False(manager.ImplementThrottling(userAFirstPort));
        Assert.True(manager.ImplementThrottling(userASecondPort));
        Assert.False(manager.ImplementThrottling(userB));
    }

    [Fact]
    public void ResolveClientIp_FallsBackToClientIpAndRemoteIp_WhenXForwardedForIsMalformed()
    {
        var withClientIp = CreateRequest(
            remoteIp: "10.0.0.5",
            xForwardedFor: "spoofed-garbage, 198.51.100.1",
            clientIp: "[2001:db8::42]:8443");
        Assert.Equal("2001:db8::42", ThrottlingManager.ResolveClientIp(withClientIp));

        var withRemoteOnly = CreateRequest(
            remoteIp: "10.0.0.5",
            xForwardedFor: ", 198.51.100.1");
        Assert.Equal("10.0.0.5", ThrottlingManager.ResolveClientIp(withRemoteOnly));

        // Direct internet callers with a public RemoteIpAddress cannot spoof X-Forwarded-For
        var directPublicCaller = CreateRequest(
            remoteIp: "8.8.4.4",
            xForwardedFor: "198.51.100.99");
        Assert.Equal("8.8.4.4", ThrottlingManager.ResolveClientIp(directPublicCaller));
    }

    [Fact]
    public void ImplementThrottling_PrunesExpiredBucketsAndCapsActiveOverflow()
    {
        var now = new DateTime(2026, 11, 13, 12, 0, 0, DateTimeKind.Utc);
        var manager = new ThrottlingManager(1000, 2, () => now, maxTrackedBuckets: 3);

        for (int i = 1; i <= 3; i++)
        {
            var req = CreateRequest(remoteIp: "10.0.0.5", xForwardedFor: $"8.8.8.{i}");
            Assert.False(manager.ImplementThrottling(req));
        }

        Assert.Equal(3, manager.TrackedBucketCount);

        // Additional active clients within the same window route into the bounded overflow bucket
        for (int i = 10; i <= 20; i++)
        {
            var overflowReq = CreateRequest(remoteIp: "10.0.0.5", xForwardedFor: $"8.8.8.{i}");
            _ = manager.ImplementThrottling(overflowReq);
        }

        Assert.Equal(4, manager.TrackedBucketCount);

        // Expire all buckets, then send one new request to trigger capacity cleanup
        now = now.AddMilliseconds(2000);
        var freshReq = CreateRequest(remoteIp: "10.0.0.5", xForwardedFor: "1.1.1.1");
        Assert.False(manager.ImplementThrottling(freshReq));

        Assert.Equal(1, manager.TrackedBucketCount);
    }

    private static HttpRequest CreateRequest(string remoteIp, string? xForwardedFor = null, string? clientIp = null)
    {
        var context = new DefaultHttpContext();
        context.Connection.RemoteIpAddress = IPAddress.Parse(remoteIp);
        if (xForwardedFor is not null)
        {
            context.Request.Headers["X-Forwarded-For"] = xForwardedFor;
        }
        if (clientIp is not null)
        {
            context.Request.Headers["Client-IP"] = clientIp;
        }

        return context.Request;
    }
}
