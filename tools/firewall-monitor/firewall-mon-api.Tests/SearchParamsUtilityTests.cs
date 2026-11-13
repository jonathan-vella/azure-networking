using firewallmon.models;
using firewallmon.utilities;
using Xunit;

namespace firewallmon.tests;

public class SearchParamsUtilityTests
{
    [Fact]
    public void EncodeAndDecode_RoundTripsAllFields()
    {
        var original = new FirewallSearchParams
        {
            Fulltext = ["azfwnetworkrule", "deny"],
            StartDate = "10:15",
            EndDate = "10:45",
            LastMinutes = 15,
            Category = ["azfwnetworkrule"],
            Protocol = ["tcp", "udp"],
            Source = ["10.1.0.4"],
            Target = ["20.50.10.1"],
            Action = ["deny"],
            Policy = ["hub-fw-policy"],
            MoreInfo = ["tls"]
        };

        string encoded = SearchParamsUtility.Encode(original);
        FirewallSearchParams decoded = SearchParamsUtility.Decode(encoded);

        Assert.Equal(original.Fulltext, decoded.Fulltext);
        Assert.Equal(original.StartDate, decoded.StartDate);
        Assert.Equal(original.EndDate, decoded.EndDate);
        Assert.Equal(original.LastMinutes, decoded.LastMinutes);
        Assert.Equal(original.Category, decoded.Category);
        Assert.Equal(original.Protocol, decoded.Protocol);
        Assert.Equal(original.Source, decoded.Source);
        Assert.Equal(original.Target, decoded.Target);
        Assert.Equal(original.Action, decoded.Action);
        Assert.Equal(original.Policy, decoded.Policy);
        Assert.Equal(original.MoreInfo, decoded.MoreInfo);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("{not-valid-json")]
    [InlineData("null")]
    public void Decode_ReturnsEmptyDefaultObject_WhenInputIsBlankOrMalformed(string input)
    {
        var result = SearchParamsUtility.Decode(input);

        Assert.NotNull(result);
        Assert.Equal(0, result.LastMinutes);
        Assert.Empty(result.Fulltext);
        Assert.Equal(string.Empty, result.StartDate);
        Assert.Equal(string.Empty, result.EndDate);
    }

    [Fact]
    public void Encode_ThrowsArgumentNullException_WhenNull()
    {
        Assert.Throws<ArgumentNullException>(() => SearchParamsUtility.Encode(null!));
    }

    [Fact]
    public void CreateDefaultParams_SetsTwelveMinutesWindow()
    {
        var defaults = SearchParamsUtility.CreateDefaultParams();
        Assert.Equal(12, defaults.LastMinutes);
    }
}
