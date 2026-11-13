namespace firewallmon.models;

public class AzureAPIResponse
{
    public CountryRegion? countryRegion { get; set; }
}

public class CountryRegion
{
    public string? isoCode { get; set; }
}