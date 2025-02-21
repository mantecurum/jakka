# Naming Conventions
# ==================

# ...A - Awk array
# ...L - list, i.e. array with only numeric keys from 0 to `n`
# ...C - count, i.e. count of elements in an accompanying list
# ...M - map, i.e. array with only non-numeric keys
# ...P - pointer, i.e. one-element array with value under `DEREF` key

# Utility Functions
# =================

# Clean an array.
function cleanA(a, _key) { for(_key in a) { delete a[_key] } }

# JSON Utility Functions
# ======================

function unwrapJsonString(jsonStr, outStrP) {
    gsub(/^[[:space:]]*"/, "", jsonStr)
    gsub(/"[[:space:]]*$/, "", jsonStr)
    gsub(/\\"/, "\"", jsonStr)
    gsub(/\\t/, "\t", jsonStr)
    gsub(/\\n/, "\n", jsonStr)
    outStrP[DEREF] = jsonStr
    return OK
}

# JSON Parsers
# ============

function parseJsonString(str, restStrP, outStrP, _outStr) {
    # first, cut out whitespace and opening double-quote:
    if(!match(str, /^[[:space:]]*"/)) return PARSE_JSON_ERR_UNPARSABLE
    _outStr = substr(str, RSTART, RLENGTH)
    str = substr(str, RLENGTH + 1)
    # then, parse as much string innards as possible:
    if(match(str, /^([^"\\]|\\["nt])*/)) {
        _outStr = _outStr substr(str, RSTART, RLENGTH)
        str = substr(str, RLENGTH + 1)
    }
    # ultimately, find the closing quote
    if(str !~ /^"/) return PARSE_JSON_ERR_UNPARSABLE
    _outStr = _outStr "\""
    str = substr(str, 2)
    # ---
    outStrP[DEREF] = outStrP[DEREF] _outStr
    restStrP[DEREF] = str
    return OK
}

function parseJsonArray(str, jsonArr, jsonArrCP, _restStrP, _outStrP, _err) {
    if(!match(str, /^[[:space:]]*\[/)) return PARSE_JSON_ERR_UNPARSABLE
    str = substr(str, RLENGTH + 1)
    cleanA(_restStrP); cleanA(_outStrP)
    while(OK == parseJsonString(str, _restStrP, _outStrP)) {
        # update restStr:
        str = _restStrP[DEREF]
        cleanA(_restStrP)
        # update outStr:
        jsonArr[jsonArrCP[DEREF]++] = _outStrP[DEREF]
        cleanA(_outStrP)
        # if there's a comma, expect next element:
        if(match(str, /^[[:space:]]*,/)) {
            str = substr(str, RLENGTH + 1)
        # otherwise, it was the last element - break the loop:
        } else break
    }
    # expect a closing square bracket:
    if(!match(str, /^[[:space:]]*\]/)) return PARSE_JSON_ERR_UNPARSABLE
    return OK
}

function extractJsonObject(str, jsonObjM, optRestStrP, _outStrP, _keyP, _err) {
    cleanA(optRestStrP); cleanA(_outStrP); cleanA(_keyP)
    optRestStrP[DEREF] = str
    # `str` won't be used in this func from now on, only `optRestStrP`
    if(!match(optRestStrP[DEREF], /^[[:space:]]*\{/)) {
        return PARSE_JSON_ERR_UNPARSABLE
    }
    optRestStrP[DEREF] = substr(optRestStrP[DEREF], RLENGTH + 1)
    while(TRUE) {
        # expect a key:
        cleanA(_outStrP); cleanA(_keyP)
        _err = parseJsonString(optRestStrP[DEREF], optRestStrP, _outStrP)
        if(_err != OK) return _err
        _err = unwrapJsonString(_outStrP[DEREF], _keyP)
        if(_err != OK) return _err
        # expect a colon:
        if(!match(optRestStrP[DEREF], /^[[:space:]]*:/)) {
            return PARSE_JSON_ERR_UNPARSABLE
        }
        optRestStrP[DEREF] = substr(optRestStrP[DEREF], RLENGTH + 1)
        # expect a value: (TODO: support other values than JSON string)
        cleanA(_outStrP); cleanA(_valueP)
        _err = parseJsonString(optRestStrP[DEREF], optRestStrP, _outStrP)
        if(_err != OK) return _err
        # put the entry to the resulting map:
        jsonObjM[_keyP[DEREF]] = _outStrP[DEREF]
        # if there's a comma, expect next entry:
        if(match(optRestStrP[DEREF], /^[[:space:]]*,/)) {
            optRestStrP[DEREF] = substr(optRestStrP[DEREF], RLENGTH + 1)
        # otherwise, it was the last entry - break the loop:
        } else break
    }
    # expect a closing brace:
    if(optRestStrP[DEREF] !~ /^[[:space:]]*}/) return PARSE_JSON_ERR_UNPARSABLE
    return OK
}

# MapExpr Constructors
# ====================

function MapExprIdentity(out, outCP) {
    out[outCP[DEREF]++] = MAPEXPR_KIND_IDENTITY
}
function MapExprArrSubscript(out, outCP, num) {
    out[outCP[DEREF]++] = MAPEXPR_KIND_ARR_SUBSCRIPT
    out[outCP[DEREF]++] = num
}
function MapExprCmd(out, outCP, cmdName) {
    out[outCP[DEREF]++] = MAPEXPR_KIND_COMMAND
    out[outCP[DEREF]++] = cmdName
}
function MapExprObjSubscript(out, outCP, fieldKey) {
    out[outCP[DEREF]++] = MAPEXPR_KIND_OBJ_SUBSCRIPT
    out[outCP[DEREF]++] = fieldKey
}

# MapExpr Parsers
# ===============

function parseMapExpr(str, out, outCP) {
    if(str ~ /^\.$/) {
        MapExprIdentity(out, outCP)
    } else if(str ~ /^\.\[[1-9][0-9]*\]$/) {
        match(str, /[1-9][0-9]*/)
        MapExprArrSubscript(out, outCP, substr(str, RSTART, RLENGTH) * 1)
    } else if(match(str, /^[_a-zA-Z]+$/)) {
        MapExprCmd(out, outCP, substr(str, RSTART, RLENGTH))
    } else if(match(str, /^\.[_a-zA-Z]+$/)) {
        MapExprObjSubscript(out, outCP, substr(str, RSTART + 1, RLENGTH - 1))
    } else return PARSE_MAPEXPR_ERR_UNPARSABLE
    return OK
}

# XXX: interpretLine prints to stdout/stderr!
function interpretLine( \
    line, mapExprL, mapExprCP, \
    _subscript, _jsonListL, _jsonListCP, \
    _err, _outStrP, _jsonObjM, \
    _restStrP \
) {
    # lazily parse and map the input value based on given map expressions:
    if(mapExprL[0] == MAPEXPR_KIND_IDENTITY) {
        print
    } else if(mapExprL[0] == MAPEXPR_KIND_ARR_SUBSCRIPT) {
        _subscript = mapExprL[1]
        cleanA(_jsonListL); cleanA(_jsonListCP)
        _jsonListCP[DEREF] = 0
        _err = parseJsonArray($0, _jsonListL, _jsonListCP)
        print _jsonListL[_subscript]
    } else if(mapExprL[0] == MAPEXPR_KIND_COMMAND) {
        if(mapExprL[1] != "unwrap") {
            print "ERROR: Unsupported command '"mapExprL[1]"'!" > "/dev/stderr"
            exit 1
        }
        cleanA(_restStrP); cleanA(_outStrP)
        _err = parseJsonString(line, _restStrP, _outStrP)
        if(_err != OK) exit _err
        _err = unwrapJsonString(_outStrP[DEREF], _outStrP)
        if(_err != OK) exit _err
        print _outStrP[DEREF]
    } else if(mapExprL[0] == MAPEXPR_KIND_OBJ_SUBSCRIPT) {
        cleanA(_jsonObjM)
        _err = extractJsonObject(line, _jsonObjM)
        if(_err != OK) exit _err
        print _jsonObjM[mapExprL[1]]
    } else {
        exit ERROR_UNSUPPORTED
    }
    # 2. try parsing a line as json value
    # 2a. if one independent value is parsed, map it and output the result
    # 2b. if the value is not finished, move to next line
}

BEGIN {
    # EXTERNAL CONSTANS
    # -----------------
    # NOTE: Errors shall be powers of two to allow stacking errors.

    ERROR_GENERIC = 1
    ERROR_UNPARSABLE = 2 # problem with parsing
    ERROR_UNSUPPORTED = 4 # operation unsupported
    ERROR_TODO2 = 8
    ERROR_TODO3 = 16
    ERROR_TODO4 = 32
    ERROR_TODO5 = 64
    ERROR_TODO6 = 128

    # Booleans used for standard awk functions
    FALSE = 0
    TRUE = 1

    # - status codes for internal ops (non-zero used for various exceptions):
    DEREF = 0
    OK = 2
    PARSE_MAPEXPR_ERR_UNPARSABLE = 3
    PARSE_JSON_ERR_UNPARSABLE = 4
    # - struct kinds:
    MAPEXPR_KIND_IDENTITY = 5
    MAPEXPR_KIND_ARR_SUBSCRIPT = 6
    MAPEXPR_KIND_COMMAND = 7
    MAPEXPR_KIND_OBJ_SUBSCRIPT = 8
    # ---
    # move client arguments from ARGV to custom args map:
    for(pos = 1; pos < ARGC; pos++) {
        args[pos - 1] = ARGV[pos]
        argsc++
        delete ARGV[pos]
    }

    if(argsc != 1) {
        print "ERROR: Currently supporting only one map-expression!" > "/dev/stderr"
        exit 1
    }

    # clean up mapexprs struct:
    cleanA(mapExprL); cleanA(mapExprCP)
    mapExprCP[DEREF] = 0

    if(OK != parseMapExpr(args[0], mapExprL, mapExprCP)) {
        print "ERROR: Couldn't parse map-expression '"args[0]"'" > "/dev/stderr"
        exit 1
    }
}
{
    interpretLine($0, mapExprL, mapExprCP)
}
