/**
 * Formats whole-currency amounts for briefing text, independent of the running
 * user's locale (so tests and agent output are stable).
 *
 * CHF uses the Swiss apostrophe separator ("CHF 12'500"); other currencies use a comma.
 */
public with sharing class CurrencyFormatter {
    public static String format(Decimal amount, String currencyCode) {
        if (amount == null) {
            return '';
        }
        String separator = currencyCode == 'CHF' ? '\'' : ',';
        Long whole = amount.setScale(0, System.RoundingMode.HALF_UP).longValue();
        String digits = String.valueOf(Math.abs(whole));

        String grouped = '';
        Integer count = 0;
        for (Integer i = digits.length() - 1; i >= 0; i--) {
            if (count > 0 && Math.mod(count, 3) == 0) {
                grouped = separator + grouped;
            }
            grouped = digits.substring(i, i + 1) + grouped;
            count++;
        }
        return (String.isBlank(currencyCode) ? '' : currencyCode + ' ') + (whole < 0 ? '-' : '') + grouped;
    }
}
