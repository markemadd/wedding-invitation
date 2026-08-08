import Foundation

// MARK: - AmortizationCalculator (blueprint Phase 4.5)
// Standard fixed-payment amortization formula. O(1) for the payment
// amount; O(termMonths) for the full schedule, which is the correct
// complexity since a schedule inherently has one row per period.
public struct AmortizationCalculator {
    public init() {}

    public func monthlyPayment(principal: Decimal, annualRate: Decimal, termMonths: Int) -> Decimal {
        let monthlyRate = annualRate / 12 / 100
        guard monthlyRate > 0 else { return principal / Decimal(termMonths) } // 0% interest edge case.
        // NSDecimalNumber supports integer exponents directly — no need to
        // detour through Double's pow() and its binary rounding.
        let ratePlusOne = NSDecimalNumber(decimal: 1 + monthlyRate)
        let factor = ratePlusOne.raising(toPower: termMonths).decimalValue
        return principal * (monthlyRate * factor) / (factor - 1)
    }

    public struct ScheduleEntry: Identifiable {
        public let month: Int
        public let payment: Decimal
        public let principalPortion: Decimal
        public let interestPortion: Decimal
        public let remainingBalance: Decimal
        public var id: Int { month }
    }

    public func fullSchedule(principal: Decimal, annualRate: Decimal, termMonths: Int) -> [ScheduleEntry] {
        let payment = monthlyPayment(principal: principal, annualRate: annualRate, termMonths: termMonths)
        let monthlyRate = annualRate / 12 / 100
        var balance = principal
        var schedule: [ScheduleEntry] = []
        for month in 1...termMonths {
            let interest = balance * monthlyRate
            let principalPortion = payment - interest
            balance -= principalPortion
            schedule.append(ScheduleEntry(
                month: month,
                payment: payment,
                principalPortion: principalPortion,
                interestPortion: interest,
                remainingBalance: max(0, balance)
            ))
        }
        return schedule
    }
}
