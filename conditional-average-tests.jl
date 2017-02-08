# This file is part of Jlsca, license is GPLv3, see https://www.gnu.org/licenses/gpl-3.0.en.html
#
# Author: Cees-Bart Breunesse

# Run: julia -p3 -Lsca.jl <thisfile>

using Base.Test

using Sca
using Trs

import Sca.FORWARD,Sca.BACKWARD,Sca.PHASE1,Sca.PHASE2,Sca.PHASE3,Sca.PHASE4,Sca.PHASE5,Sca.PHASE6,Sca.SBOX,Sca.ROUNDOUT,Sca.TDES1,Sca.TDES2,Sca.TDES3

function ParallelCondAvgTest(splitmode)
    len = 200

    fullfilename = "aestraces/aes128_sb_ciph_0fec9ca47fb2f2fd4df14dcb93aa4967.trs"
    @printf("file: %s\n", fullfilename)

    direction = FORWARD
    params = getParameters(fullfilename, direction)

    params.analysis = DPA()
    params.analysis.statistic = cor
    params.analysis.leakageFunctions = [hw]

    numberOfAverages = length(params.keyByteOffsets)
    numberOfCandidates = getNumberOfCandidates(params)

    @everyworker begin
      using Trs
      trs = InspectorTrace($fullfilename)
      if $splitmode == 1
        setPostProcessor(trs, CondAvg(SplitByTracesSliced()))
      elseif $splitmode == 2
        setPostProcessor(trs, CondAvg(SplitByTracesBlock()))
      elseif $splitmode == 3
        setPostProcessor(trs, CondAvg(SplitByData($numberOfAverages, $numberOfCandidates)))
      end
    end

    sando = Vector{Tuple{Matrix{Float64}, Matrix{UInt}}}(2)
    sandoIdx = 1

    cb::Function = (phase,params,scoresAndOffsets,dataWidth,keyOffsets,numberOfTraces2) -> (sando[sandoIdx] = scoresAndOffsets[1]; sandoIdx += 1)

    key = sca(DistributedTrace(),params,1, len, false, Nullable{Function}(cb))

    @test(key == get(params.knownKey))

    params.analysis = DPA()
    params.analysis.statistic = cor
    params.analysis.leakageFunctions = [hw]

    trs = InspectorTrace(fullfilename)
    setPostProcessor(trs, CondAvg(NoSplit()))

    key = sca(trs,params,1, len, false, Nullable{Function}(cb))

    @test(key == get(params.knownKey))

    @test sandoIdx == 3

    @test_approx_eq sando[1][1] sando[2][1]
    @test sando[1][2] == sando[2][2]
end

function ParallelCondAvgTestWithInterval()
    len = 200
    updateInterval = 49

    fullfilename = "aestraces/aes128_sb_ciph_0fec9ca47fb2f2fd4df14dcb93aa4967.trs"
    @printf("file: %s\n", fullfilename)

    direction = FORWARD
    params = getParameters(fullfilename, direction)

    params.analysis = DPA()
    params.analysis.statistic = cor
    params.analysis.leakageFunctions = [hw]
    params.updateInterval = Nullable(updateInterval)

    numberOfAverages = length(params.keyByteOffsets)
    numberOfCandidates = getNumberOfCandidates(params)

    @everyworker begin
      using Trs
      trs = InspectorTrace($fullfilename)
      setPostProcessor(trs, CondAvg(SplitByTracesSliced()))
    end

    numberOfScas = div(len, 50) + ((len % updateInterval) > 0 ? 1 : 0)
    sando = Vector{Tuple{Matrix{Float64}, Matrix{UInt}}}(numberOfScas*2)
    sandoIdx = 1

    cb::Function = (phase,params,scoresAndOffsets,dataWidth,keyOffsets,numberOfTraces2) -> (sando[sandoIdx] = scoresAndOffsets[1]; sandoIdx += 1)

    key = sca(DistributedTrace(),params,1, len, false, Nullable{Function}(cb))

    @test(key == get(params.knownKey))

    params.analysis = DPA()
    params.analysis.statistic = cor
    params.analysis.leakageFunctions = [hw]
    params.updateInterval = Nullable()

    for s in 1:numberOfScas
      len2 = min(len, updateInterval*s)

      trs = InspectorTrace(fullfilename)
      setPostProcessor(trs, CondAvg(NoSplit()))

      key = sca(trs,params,1, len2, false, Nullable{Function}(cb))

      @test(key == get(params.knownKey))
    end

    @test sandoIdx == numberOfScas*2+1

    for s in 1:numberOfScas
      @test_approx_eq sando[s][1] sando[s][1]
      @test sando[s][2] == sando[s][2]
    end
end


@assert nworkers() > 1

ParallelCondAvgTest(1)
ParallelCondAvgTest(2)
ParallelCondAvgTest(3)

ParallelCondAvgTestWithInterval()
