package lex

import "math"

// decEnd returns the end of the {decinteger} that starts at p, or p when
// there is none: digits, with single underscores between digits.
func decEnd(src string, p int) int {
	if p >= len(src) || !isDigit(src[p]) {
		return p
	}
	p++
	for p < len(src) {
		switch {
		case isDigit(src[p]):
			p++
		case src[p] == '_' && p+1 < len(src) && isDigit(src[p+1]):
			p += 2
		default:
			return p
		}
	}
	return p
}

// prefixedEnd matches 0[xX](_?hexdigit)+ and its octal and binary
// relatives; it returns p when the text does not match.
func prefixedEnd(src string, p int, lower, upper byte, digit func(byte) bool) int {
	if p+1 >= len(src) || src[p] != '0' || (src[p+1] != lower && src[p+1] != upper) {
		return p
	}
	i, n := p+2, 0
	for i < len(src) {
		switch {
		case digit(src[i]):
			i++
			n++
		case src[i] == '_' && i+1 < len(src) && digit(src[i+1]):
			i += 2
			n++
		default:
			if n == 0 {
				return p
			}
			return i
		}
	}
	if n == 0 {
		return p
	}
	return i
}

// failEnd matches the {hexfail}, {octfail} and {binfail} patterns 0[xX]_?.
func failEnd(src string, p int, lower, upper byte) int {
	if p+1 >= len(src) || src[p] != '0' || (src[p+1] != lower && src[p+1] != upper) {
		return p
	}
	e := p + 2
	if e < len(src) && src[e] == '_' {
		e++
	}
	return e
}

// junkEnd returns the end of {identifier} at p, or p when there is none.
func junkEnd(src string, p int) int {
	if p >= len(src) || !identStart(src[p]) {
		return p
	}
	p++
	for p < len(src) && identCont(src[p]) {
		p++
	}
	return p
}

// junkMax returns the end of the longest match of {X}{identifier}, where X
// is a number rule that matches src[p:xE]; 0 when there is no match. A regular
// expression may split the text anywhere, so besides the end of X the number
// may be cut at an underscore inside it: in 1_0$ the number is 1 and the
// identifier is _0$.
func junkMax(src string, p, xE int) int {
	best := 0
	if e := junkEnd(src, xE); e > xE {
		best = e
	}
	for i := p + 1; i < xE; i++ {
		if src[i] == '_' && isDigit(src[i-1]) {
			if e := junkEnd(src, i); e > best {
				best = e
			}
		}
	}
	return best
}

func isOct(c byte) bool { return c >= '0' && c <= '7' }
func isBin(c byte) bool { return c == '0' || c == '1' }

// Rules of scan.l for numbers, in file order. When two rules match the same
// amount of input the earlier one wins, as in flex.
const (
	ruleDec = iota
	ruleHex
	ruleOct
	ruleBin
	ruleHexFail
	ruleOctFail
	ruleBinFail
	ruleNumeric
	ruleNumericFail
	ruleReal
	ruleRealFail
	ruleIntegerJunk
	ruleNumericJunk
	ruleRealJunk
	numRules
)

// number scans the number that starts at p: a digit, or a dot followed by a
// digit.
func (s *Scanner) number(p int) (Item, error) {
	src := s.src
	var end [numRules]int // end of the match of each rule; 0 means no match

	dE := decEnd(src, p)
	if dE > p {
		end[ruleDec] = dE
	}
	end[ruleHex] = nz(prefixedEnd(src, p, 'x', 'X', isHex), p)
	end[ruleOct] = nz(prefixedEnd(src, p, 'o', 'O', isOct), p)
	end[ruleBin] = nz(prefixedEnd(src, p, 'b', 'B', isBin), p)
	end[ruleHexFail] = nz(failEnd(src, p, 'x', 'X'), p)
	end[ruleOctFail] = nz(failEnd(src, p, 'o', 'O'), p)
	end[ruleBinFail] = nz(failEnd(src, p, 'b', 'B'), p)

	// {numeric}: digits "." digits? | "." digits
	nE := p
	if dE > p {
		if dE < len(src) && src[dE] == '.' {
			nE = decEnd(src, dE+1)
		}
	} else if src[p] == '.' {
		nE = decEnd(src, p+1)
	}
	if nE > p {
		end[ruleNumeric] = nE
	}
	// {numericfail}: digits ".."
	if dE > p && dE+1 < len(src) && src[dE] == '.' && src[dE+1] == '.' {
		end[ruleNumericFail] = dE + 2
	}
	// {real} and {realfail}: (decinteger | numeric) [Ee] [-+]? decinteger
	base := dE
	if nE > p {
		base = nE
	}
	realE := p
	if base > p && base < len(src) && (src[base] == 'e' || src[base] == 'E') {
		e := base + 1
		signed := false
		if e < len(src) && (src[e] == '+' || src[e] == '-') {
			signed = true
			e++
		}
		if d := decEnd(src, e); d > e {
			realE = d
			end[ruleReal] = d
		}
		if signed {
			end[ruleRealFail] = base + 2
		}
	}
	// junk: a number directly followed by an identifier
	if dE > p {
		end[ruleIntegerJunk] = junkMax(src, p, dE)
	}
	if nE > p {
		end[ruleNumericJunk] = junkMax(src, p, nE)
	}
	if realE > p {
		end[ruleRealJunk] = junkMax(src, p, realE)
	}

	best := -1
	for r := 0; r < numRules; r++ {
		if end[r] > 0 && (best < 0 || end[r] > end[best]) {
			best = r
		}
	}
	switch best {
	case ruleDec, ruleHex, ruleOct, ruleBin:
		return s.integer(p, end[best]), nil
	case ruleHexFail:
		return Item{}, s.errorAt("invalid hexadecimal integer", p, end[best])
	case ruleOctFail:
		return Item{}, s.errorAt("invalid octal integer", p, end[best])
	case ruleBinFail:
		return Item{}, s.errorAt("invalid binary integer", p, end[best])
	case ruleNumeric, ruleReal:
		it := s.item(FCONST, p, end[best])
		it.Str = src[p:end[best]]
		return it, nil
	case ruleNumericFail:
		// 1..10 is 1, "..", 10: give back the dots
		return s.integer(p, dE), nil
	}
	return Item{}, s.errorAt("trailing junk after numeric literal", p, end[best])
}

// nz returns e, or 0 when e == p (the rule did not match, or the junk part
// is empty).
func nz(e, p int) int {
	if e == p {
		return 0
	}
	return e
}

// integer is process_integer_literal: an integer that fits int32 is an
// ICONST, anything else is an FCONST with the text as written.
func (s *Scanner) integer(p, e int) Item {
	text := s.src[p:e]
	base := uint64(10)
	i := 0
	if len(text) > 2 && text[0] == '0' {
		switch text[1] {
		case 'x', 'X':
			base, i = 16, 2
		case 'o', 'O':
			base, i = 8, 2
		case 'b', 'B':
			base, i = 2, 2
		}
	}
	var v uint64
	for ; i < len(text); i++ {
		c := text[i]
		if c == '_' {
			continue
		}
		v = v*base + uint64(hexVal(c))
		if v > math.MaxInt32 {
			it := s.item(FCONST, p, e)
			it.Str = text
			return it
		}
	}
	it := s.item(ICONST, p, e)
	it.Int = int32(v)
	return it
}
