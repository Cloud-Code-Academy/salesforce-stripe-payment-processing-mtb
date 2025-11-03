/**
 * @description Exception thrown when a card-related error occurs in Stripe API (card_error type).
 *              This is the most common error type and occurs when a card cannot be charged due to
 *              issues like insufficient funds, card declined, expired card, incorrect CVC, etc.
 *              Inherits all constructors from StripeException and Exception.
 */
public class StripeCardException extends StripeException {
}