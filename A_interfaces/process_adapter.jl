# Two explicit IPC paths: a persistent process and a newly launched process.
# The external response is parsed by plain Julia for the independent check.
include(joinpath(@__DIR__, "..", "lib", "poly.jl"))
const SYSTEM = SYSTEM_KEY == "maxima" ? "Maxima" : "FriCAS"
const VAR = Dict{Symbol,Any}()
const EXECUTABLE = get(ENV, SYSTEM_KEY == "maxima" ? "MAXIMA" : "FRICAS", SYSTEM_KEY)
const SESSION = Ref{Any}(nothing)
const COUNTER = Ref(0)
const OPS = Dict{Symbol,Any}()
struct InterfaceAnswer
    text::String
end
Base.string(a::InterfaceAnswer) = a.text
function EVAL(a::InterfaceAnswer, values)
    p = try Poly.parse_poly(a.text, ["x", "y"]) catch; return nothing end
    sum(Float64(c) * values[:x]^m[1] * values[:y]^m[2] for (m, c) in p; init=0.0)
end
UNSOLVED(op, out) = false
CLEARCACHE() = nothing
function VERSIONS()
    cmd = SYSTEM_KEY == "maxima" ? `$EXECUTABLE --version` : `$EXECUTABLE -nosman -eval ")version"`
    version = try strip(read(pipeline(`timeout -k 2 10 $cmd`; stderr=devnull), String)) catch; "unknown" end
    [SYSTEM => first(replace(version, '\n' => ' '), 120)]
end

function interface_command(input, marker)
    # Split the marker in the command to avoid mistaking echoed input for output.
    left, right = marker[1:8], marker[9:end]
    if SYSTEM_KEY == "maxima"
        "display2d:false\$\nlinel:1000000\$\nprint(concat(\"$left\",\"$right\"),string(expand($input)))\$\n"
    else
        ")set message autoload off\n)set message type off\n)set output algebra off\noutput(concat(concat(\"$left\",\"$right\"),unparse(($input)::InputForm)))\n)lisp (finish-output)\n"
    end
end

function interface_session(input; cold=false)
    COUNTER[] += 1
    marker = "CASBENCH" * string(COUNTER[]) * "END"
    script = interface_command(input, marker)
    isempty(INPUT_LOG) && log_input!(script)
    cmd = SYSTEM_KEY == "maxima" ? `$EXECUTABLE --very-quiet` : `$EXECUTABLE -nosman`
    io = if cold || SESSION[] === nothing || !isopen(SESSION[])
        open(pipeline(cmd; stderr=devnull), "r+")
    else
        SESSION[]
    end
    cold || (SESSION[] = io)
    try
        write(io, script); flush(io)
        while !eof(io)
            line = readline(io)
            pos = findfirst(marker, line)
            pos === nothing && continue
            answer = strip(line[nextind(line, last(pos)):end])
            isempty(answer) && error("empty external response")
            return InterfaceAnswer(answer)
        end
        error("external process exited without a response")
    finally
        cold && close(io)
    end
end
OPS[:interface_session] = input -> interface_session(input)
OPS[:interface_cold] = input -> interface_session(input; cold=true)
atexit(() -> (SESSION[] === nothing || !isopen(SESSION[]) || close(SESSION[])))
