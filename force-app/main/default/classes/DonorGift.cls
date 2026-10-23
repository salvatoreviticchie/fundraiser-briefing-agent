/**
 * Immutable value object for one received gift.
 *
 * The scoring classes work on DonorGift rather than Opportunity so they stay
 * pure (no SOQL, no DML) and can be unit-tested with plain in-memory data.
 * Swapping the gift source later (e.g. Nonprofit Cloud GiftTransaction) only
 * means changing the mapping in DonorBriefingService.
 */
public with sharing class DonorGift implements Comparable {
    public final Decimal amount;
    public final Date giftDate;

    public DonorGift(Decimal amount, Date giftDate) {
        this.amount = amount;
        this.giftDate = giftDate;
    }

    /** Sorts oldest first. */
    public Integer compareTo(Object other) {
        Date otherDate = ((DonorGift) other).giftDate;
        if (giftDate == otherDate) {
            return 0;
        }
        return giftDate < otherDate ? -1 : 1;
    }
}
