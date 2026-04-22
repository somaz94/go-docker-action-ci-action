package main

import "testing"

func TestGreet(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		in   string
		want string
	}{
		{name: "default", in: "", want: "hello, world"},
		{name: "explicit", in: "somaz", want: "hello, somaz"},
		{name: "whitespace is preserved", in: "  bob  ", want: "hello,   bob  "},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := greet(tc.in); got != tc.want {
				t.Fatalf("greet(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}
