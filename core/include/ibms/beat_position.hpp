#pragma once

#include <cstdint>
#include <limits>
#include <stdexcept>
#include <utility>

namespace ibms {

/// An exact, normalized rational position measured in beats.
///
/// Values are stored as numerator / denominator with a positive denominator,
/// no common factors, and zero represented as 0 / 1. Construction with a zero
/// denominator throws std::invalid_argument. Arithmetic throws
/// std::overflow_error when its normalized result is outside int64_t; division
/// by zero throws std::domain_error.
///
/// This core currently requires compiler support for __int128 (Clang and GCC).
class BeatPosition final {
public:
    using rep = std::int64_t;

    /// Creates numerator / denominator and normalizes it exactly.
    explicit BeatPosition(rep numerator = 0, rep denominator = 1) {
        const auto normalized = normalize(static_cast<wide>(numerator), static_cast<wide>(denominator));
        numerator_ = normalized.first;
        denominator_ = normalized.second;
    }

    [[nodiscard]] rep numerator() const noexcept { return numerator_; }
    [[nodiscard]] rep denominator() const noexcept { return denominator_; }

    friend bool operator==(const BeatPosition&, const BeatPosition&) noexcept = default;

    friend bool operator<(const BeatPosition& left, const BeatPosition& right) noexcept {
        return static_cast<wide>(left.numerator_) * right.denominator_
            < static_cast<wide>(right.numerator_) * left.denominator_;
    }

    friend bool operator>(const BeatPosition& left, const BeatPosition& right) noexcept {
        return right < left;
    }

    friend bool operator<=(const BeatPosition& left, const BeatPosition& right) noexcept {
        return !(right < left);
    }

    friend bool operator>=(const BeatPosition& left, const BeatPosition& right) noexcept {
        return !(left < right);
    }

    friend BeatPosition operator+(const BeatPosition& left, const BeatPosition& right) {
        return from_wide(
            static_cast<wide>(left.numerator_) * right.denominator_
                + static_cast<wide>(right.numerator_) * left.denominator_,
            static_cast<wide>(left.denominator_) * right.denominator_);
    }

    friend BeatPosition operator-(const BeatPosition& left, const BeatPosition& right) {
        return from_wide(
            static_cast<wide>(left.numerator_) * right.denominator_
                - static_cast<wide>(right.numerator_) * left.denominator_,
            static_cast<wide>(left.denominator_) * right.denominator_);
    }

    friend BeatPosition operator*(const BeatPosition& left, const BeatPosition& right) {
        return from_wide(
            static_cast<wide>(left.numerator_) * right.numerator_,
            static_cast<wide>(left.denominator_) * right.denominator_);
    }

    friend BeatPosition operator/(const BeatPosition& left, const BeatPosition& right) {
        if (right.numerator_ == 0) {
            throw std::domain_error("cannot divide a beat position by zero");
        }
        return from_wide(
            static_cast<wide>(left.numerator_) * right.denominator_,
            static_cast<wide>(left.denominator_) * right.numerator_);
    }

private:
    using wide = __int128;
    using unsigned_wide = unsigned __int128;

    rep numerator_ = 0;
    rep denominator_ = 1;

    [[nodiscard]] static unsigned_wide magnitude(wide value) noexcept {
        return value < 0 ? unsigned_wide{0} - static_cast<unsigned_wide>(value)
                         : static_cast<unsigned_wide>(value);
    }

    [[nodiscard]] static unsigned_wide gcd(unsigned_wide left, unsigned_wide right) noexcept {
        while (right != 0) {
            const unsigned_wide remainder = left % right;
            left = right;
            right = remainder;
        }
        return left;
    }

    [[nodiscard]] static rep checked_rep(wide value) {
        constexpr wide minimum = static_cast<wide>(std::numeric_limits<rep>::min());
        constexpr wide maximum = static_cast<wide>(std::numeric_limits<rep>::max());
        if (value < minimum || value > maximum) {
            throw std::overflow_error("beat position result is outside int64_t range");
        }
        return static_cast<rep>(value);
    }

    [[nodiscard]] static std::pair<rep, rep> normalize(wide numerator, wide denominator) {
        if (denominator == 0) {
            throw std::invalid_argument("a beat position denominator must not be zero");
        }
        if (numerator == 0) {
            return {0, 1};
        }
        if (denominator < 0) {
            numerator = -numerator;
            denominator = -denominator;
        }

        const unsigned_wide divisor = gcd(magnitude(numerator), magnitude(denominator));
        numerator /= static_cast<wide>(divisor);
        denominator /= static_cast<wide>(divisor);
        return {checked_rep(numerator), checked_rep(denominator)};
    }

    [[nodiscard]] static BeatPosition from_wide(wide numerator, wide denominator) {
        const auto normalized = normalize(numerator, denominator);
        BeatPosition result;
        result.numerator_ = normalized.first;
        result.denominator_ = normalized.second;
        return result;
    }
};

}  // namespace ibms
