/**
 * @description Exception thrown when a card-related error occurs in Stripe API (card_error type).
 *              This is the most common error type and occurs when a card cannot be charged due to
 *              issues like insufficient funds, card declined, expired card, incorrect CVC, etc.
 */
public class StripeCardException extends StripeException {
    /**
     * @description Constructor that creates a card exception with a message.
     * @param message The error message describing the card error
     */
    public StripeCardException(String message) {
        super(message);
    }
}
