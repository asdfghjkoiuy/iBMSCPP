#include <ibms/beat_position.hpp>

#include <cstdint>
#include <exception>
#include <iostream>
#include <limits>
#include <random>
#include <stdexcept>
#include <string_view>

namespace {

using Wide = __int128;
using UnsignedWide = unsigned __int128;

int failures = 0;

void expect(bool condition, std::string_view expression) {
    if (!condition) {
        std::cerr << "Expectation failed: " << expression << '\n';
        ++failures;
    }
}

template <typename Exception, typename Operation>
void expect_throws(Operation&& operation, std::string_view expression) {
    try {
        operation();
        std::cerr << "Expected exception was not thrown: " << expression << '\n';
        ++failures;
    } catch (const Exception&) {
    } catch (const std::exception& exception) {
        std::cerr << "Unexpected exception for " << expression << ": " << exception.what() << '\n';
        ++failures;
    }
}

[[nodiscard]] UnsignedWide magnitude(Wide value) {
    return value < 0 ? UnsignedWide{0} - static_cast<UnsignedWide>(value)
                     : static_cast<UnsignedWide>(value);
}

[[nodiscard]] UnsignedWide gcd(UnsignedWide left, UnsignedWide right) {
    while (right != 0) {
        const UnsignedWide remainder = left % right;
        left = right;
        right = remainder;
    }
    return left;
}

struct ReferencePosition {
    Wide numerator;
    Wide denominator;
};

[[nodiscard]] ReferencePosition reference_normalize(Wide numerator, Wide denominator) {
    if (numerator == 0) {
        return {0, 1};
    }
    if (denominator < 0) {
        numerator = -numerator;
        denominator = -denominator;
    }
    const UnsignedWide divisor = gcd(magnitude(numerator), magnitude(denominator));
    return {numerator / static_cast<Wide>(divisor), denominator / static_cast<Wide>(divisor)};
}

[[nodiscard]] ReferencePosition as_reference(const ibms::BeatPosition& position) {
    return {position.numerator(), position.denominator()};
}

[[nodiscard]] ReferencePosition add(ReferencePosition left, ReferencePosition right) {
    return reference_normalize(
        left.numerator * right.denominator + right.numerator * left.denominator,
        left.denominator * right.denominator);
}

[[nodiscard]] ReferencePosition subtract(ReferencePosition left, ReferencePosition right) {
    return reference_normalize(
        left.numerator * right.denominator - right.numerator * left.denominator,
        left.denominator * right.denominator);
}

[[nodiscard]] ReferencePosition multiply(ReferencePosition left, ReferencePosition right) {
    return reference_normalize(left.numerator * right.numerator, left.denominator * right.denominator);
}

[[nodiscard]] ReferencePosition divide(ReferencePosition left, ReferencePosition right) {
    return reference_normalize(left.numerator * right.denominator, left.denominator * right.numerator);
}

void expect_matches(const ibms::BeatPosition& actual, ReferencePosition expected, std::string_view expression) {
    expect(static_cast<Wide>(actual.numerator()) == expected.numerator
               && static_cast<Wide>(actual.denominator()) == expected.denominator,
           expression);
}

void normalization_and_boundaries() {
    using ibms::BeatPosition;
    constexpr auto minimum = std::numeric_limits<std::int64_t>::min();

    expect(BeatPosition{6, -8} == BeatPosition{-3, 4}, "6/-8 normalizes to -3/4");
    expect(BeatPosition{-6, -8} == BeatPosition{3, 4}, "-6/-8 normalizes to 3/4");
    expect(BeatPosition{0, -5} == BeatPosition{0, 1}, "zero has canonical denominator one");
    expect(BeatPosition{minimum, minimum} == BeatPosition{1, 1}, "INT64_MIN/INT64_MIN normalizes safely");
    expect_throws<std::invalid_argument>([] { static_cast<void>(BeatPosition{1, 0}); }, "zero denominator");
    expect_throws<std::overflow_error>([] { static_cast<void>(BeatPosition{1, minimum}); },
                                       "unrepresentable positive denominator");
}

void boundary_arithmetic() {
    using ibms::BeatPosition;
    constexpr auto maximum = std::numeric_limits<std::int64_t>::max();
    constexpr auto minimum = std::numeric_limits<std::int64_t>::min();

    expect(BeatPosition{} + BeatPosition{7, 13} == BeatPosition{7, 13}, "zero is the additive identity");
    expect(BeatPosition{} * BeatPosition{7, 13} == BeatPosition{}, "zero multiplication stays canonical");
    expect(BeatPosition{} / BeatPosition{7, 13} == BeatPosition{}, "zero division stays canonical");
    expect(BeatPosition{} / BeatPosition{minimum, 1} == BeatPosition{}, "zero divided by INT64_MIN stays canonical");
    expect(BeatPosition{minimum, 1} - BeatPosition{minimum, 1} == BeatPosition{},
           "INT64_MIN minus itself is zero");
    expect(BeatPosition{maximum, 2} + BeatPosition{-maximum, 3} == BeatPosition{maximum, 6},
           "addition retains a result after cross-products cancel");
    expect(BeatPosition{maximum, 2} * BeatPosition{2, maximum} == BeatPosition{1, 1},
           "multiplication reduces exactly");
    expect(BeatPosition{minimum, 3} / BeatPosition{minimum, 3} == BeatPosition{1, 1},
           "division cancels INT64_MIN safely");
    expect_throws<std::domain_error>([] { static_cast<void>(BeatPosition{1, 2} / BeatPosition{}); },
                                     "division by zero position");
    expect_throws<std::overflow_error>([] { static_cast<void>(BeatPosition{minimum, -1}); },
                                       "INT64_MIN over negative one cannot be constructed");
    expect_throws<std::overflow_error>([] { static_cast<void>(BeatPosition{minimum, 1} + BeatPosition{minimum, 1}); },
                                       "INT64_MIN plus INT64_MIN overflows");
    expect_throws<std::overflow_error>([] { static_cast<void>(BeatPosition{minimum, 1} * BeatPosition{minimum, 1}); },
                                       "INT64_MIN times INT64_MIN overflows");
    expect_throws<std::overflow_error>([] { static_cast<void>(BeatPosition{minimum, 1} / BeatPosition{-1, 1}); },
                                       "INT64_MIN division by negative one overflows");
    expect_throws<std::overflow_error>([] { static_cast<void>(BeatPosition{maximum, 1} + BeatPosition{1, 1}); },
                                       "addition result overflow");
    expect_throws<std::overflow_error>([] { static_cast<void>(BeatPosition{1, maximum} * BeatPosition{1, maximum}); },
                                       "denominator result overflow");
    expect_throws<std::overflow_error>([] {
        static_cast<void>(BeatPosition{1, maximum} - BeatPosition{-1, maximum - 1});
    }, "near-maximum denominators can produce an unrepresentable normalized numerator");
}

void extreme_comparisons() {
    using ibms::BeatPosition;
    constexpr auto maximum = std::numeric_limits<std::int64_t>::max();
    constexpr auto minimum = std::numeric_limits<std::int64_t>::min();

    expect(BeatPosition{minimum, maximum} < BeatPosition{-1, 1}, "negative comparison handles INT64_MIN");
    expect(BeatPosition{maximum, maximum - 1} > BeatPosition{1, 1}, "comparison handles large near-one values");
    expect(BeatPosition{maximum, maximum - 1} > BeatPosition{maximum - 1, maximum},
           "comparison uses wide cross-products");
}

void seeded_randomized_reference_checks() {
    using ibms::BeatPosition;
    std::mt19937_64 generator{0xB347051710ULL};
    std::uniform_int_distribution<std::int64_t> numerator_distribution{-1'000'000, 1'000'000};
    std::uniform_int_distribution<std::int64_t> denominator_distribution{1, 10'000};

    for (int index = 0; index < 2'000; ++index) {
        const BeatPosition left{numerator_distribution(generator), denominator_distribution(generator)};
        const BeatPosition right{numerator_distribution(generator), denominator_distribution(generator)};
        const ReferencePosition expected_left = as_reference(left);
        const ReferencePosition expected_right = as_reference(right);

        expect_matches(left + right, add(expected_left, expected_right), "randomized addition matches reference");
        expect_matches(left - right, subtract(expected_left, expected_right), "randomized subtraction matches reference");
        expect_matches(left * right, multiply(expected_left, expected_right), "randomized multiplication matches reference");
        if (right.numerator() != 0) {
            expect_matches(left / right, divide(expected_left, expected_right), "randomized division matches reference");
        }

        const bool expected_less = expected_left.numerator * expected_right.denominator
            < expected_right.numerator * expected_left.denominator;
        expect((left < right) == expected_less, "randomized comparison matches reference");
    }
}

}  // namespace

int main() {
    normalization_and_boundaries();
    boundary_arithmetic();
    extreme_comparisons();
    seeded_randomized_reference_checks();

    if (failures != 0) {
        std::cerr << failures << " test expectation(s) failed\n";
        return 1;
    }
    return 0;
}
