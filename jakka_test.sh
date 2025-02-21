# To be run by bashunit.

# shellcheck shell=bash

jakka()
{
	awk -f ./jakka.awk "$@"
}

feed()
{
	{
		shift && "$@"
	} <<- EOF
		${1?}
	EOF
}

test_jakka_exists()
{
	assert_equals yes "$([ -f ./jakka.awk ] && echo yes)"
}

test_jakka_identity_on_string()
{
	assert_equals '"foo"' "$(feed '"foo"' jakka .)"
}

test_jakka_subscript_on_array()
{
	assert_equals '"bar"' "$(feed '["foo","bar","baz"]' jakka '.[1]')"
}

test_jakka_unwrap_func()
{
	assert_equals foobar "$(feed '"foobar"' jakka 'unwrap')"
}

test_jakka_field_access()
{
	assert_equals '"bar"' "$(feed '{"foo":"bar","baz":"kux"}' jakka .foo)"
}

# TODO: support JSON booleans, nulls, integers, floats
# TODO: support nested complex JSON values
# TODO: map-expressions: pipe syntax
# TODO: map-expressions: nested & mixed array subscripting/object field access
# TODO: proper exception reporting and proper exit codes
# TODO: map-expressions: tuple syntax
