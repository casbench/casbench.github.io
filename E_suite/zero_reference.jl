# Reference for a near-integer control, independently evaluated in Julia.
# exp(pi*sqrt(163)) is close to, but strictly less than, the integer below.
# Every operation is monotone on these positive inputs. Directed MPFR rounding
# therefore encloses the exact real value; no decimal approximation is pasted.
const HARDY_INTEGER = big"262537412640768744"

function hardy_reference_interval(; bits = 256)
    setprecision(BigFloat, bits) do
        lo = setrounding(BigFloat, RoundDown) do
            exp(BigFloat(pi) * sqrt(BigFloat(163))) - BigFloat(HARDY_INTEGER)
        end
        hi = setrounding(BigFloat, RoundUp) do
            exp(BigFloat(pi) * sqrt(BigFloat(163))) - BigFloat(HARDY_INTEGER)
        end
        (lo, hi)
    end
end

# 10^-30 is exact and deliberately smaller than Float64 cancellation noise.
function rational_control_interval(; bits = 256)
    setprecision(BigFloat, bits) do
        den = BigFloat(big(10)^30)
        lo = setrounding(BigFloat, RoundDown) do; BigFloat(1) / den; end
        hi = setrounding(BigFloat, RoundUp) do; BigFloat(1) / den; end
        (lo, hi)
    end
end
