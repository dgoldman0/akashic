# Semantic resource references

`akashic/runtime/resource-ref.f` defines the pointer-free `RREF` identity used
by live resource registries and lens bindings. An RREF contains a stable RID
and a nonnegative revision; it contains no path, component pointer, handler,
capability, or authority.

Revision zero requests the current live component revision. A positive
revision is an optimistic exact requirement in that component's activation.
It is not automatically a durable document or domain revision. An owner may
explicitly define those spaces to be identical, but callers must not infer
that relationship from `RREF` or `LBIND` alone.

Durable qualified locators therefore embed an RREF at revision zero and carry
their positive domain revision and digest evidence in separate QLOC fields.
A cold owner activation may legitimately restart its component revision at
one while retaining durable bytes; that restart does not rewrite history.

The 80-byte version-1 representation is pointer-free. `RREF-INIT`,
`RREF-VALID?`, `RREF-COPY`, `RREF-ID=`, and `RREF=` operate on caller-owned
storage. Persisted protocols should require the exact ABI size and zero
reserved bytes in addition to ordinary runtime validity.
