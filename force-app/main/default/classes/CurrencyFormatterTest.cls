@IsTest
private class CurrencyFormatterTest {
    @IsTest
    static void formatsSwissFrancsWithApostrophe() {
        Assert.areEqual('CHF 0', CurrencyFormatter.format(0, 'CHF'));
        Assert.areEqual('CHF 999', CurrencyFormatter.format(999, 'CHF'));
        Assert.areEqual('CHF 1\'000', CurrencyFormatter.format(1000, 'CHF'));
        Assert.areEqual('CHF 1\'234\'568', CurrencyFormatter.format(1234567.6, 'CHF'), 'Rounds half up');
    }

    @IsTest
    static void formatsOtherCurrenciesWithComma() {
        Assert.areEqual('USD 12,500', CurrencyFormatter.format(12500, 'USD'));
        Assert.areEqual('12,500', CurrencyFormatter.format(12500, null));
    }

    @IsTest
    static void handlesNegativeAndNull() {
        Assert.areEqual('CHF -1\'500', CurrencyFormatter.format(-1500, 'CHF'));
        Assert.areEqual('', CurrencyFormatter.format(null, 'CHF'));
    }
}
