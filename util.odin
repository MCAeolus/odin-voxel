package main

collect_keys :: proc(m: map[$N]$E) -> [dynamic]N {
	out := make([dynamic]N)
	for k,v in m {
		append(&out, k)
	}
	return out
}
