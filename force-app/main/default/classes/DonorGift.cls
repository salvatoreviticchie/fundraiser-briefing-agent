/**
 * Immutable value object for one received gift.
 *
 * The scoring classes work on DonorGift rather than Opportunity so they stay
 * pure (no SOQL, no DML) and can be unit-tested with plain in-memory data.
 * Swapping the gift source later (e.g. Nonprofit Cloud GiftTransaction) only
 * means changing the mapping in DonorBriefingService.
 */
public with sharing class DonorGift implements Comparable {
    /** API name of the Opportunity.Gift_Type__c value for monthly/recurring gifts. */
    public static final String TYPE_RECURRING = 'Recurring';

    public final Decimal amount;
    public final Date giftDate;
    public final String giftType;

    public DonorGift(Decimal amount, Date giftDate) {
        this(amount, giftDate, null);
    }

    public DonorGift(Decimal amount, Date giftDate, String giftType) {
        this.amount = amount;
        this.giftDate = giftDate;
        this.giftType = giftType;
    }

    public Boolean isRecurring() {
        return giftType == TYPE_RECURRING;
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
