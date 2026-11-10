# SLH-DSA known answers

`akashic/math/sphincs-plus.f` implements SLH-DSA-SHAKE-128s (FIPS 205).
`local_testing/test_sphincs.py` checks it against the files here, which
OpenSSL 3.5.2 produced.

| File | Bytes | SHA-256 |
|---|---:|---|
| `shake-128s-seed-00-2f.pub` | 32 | `00bcf55c114dd213b09d26bf41dbc06a423ca37c5a52d912c0d8a376ca99bf9f` |
| `shake-128s-seed-00-2f-dead.sig` | 7,856 | `2b07b63a1ffb521b76baeabb7f220b66e76e918bedbf00691649b3c2041c6fa8` |

The key pair comes from the 48-byte seed `00 01 .. 2f`, which is SK.seed,
SK.prf and PK.seed in that order. The public key file holds PK.seed and
PK.root. The signature signs the two-byte message `DE AD`
deterministically through the standard's internal interface
(`slh_sign_internal`, which hashes the message as given), the interface
`SPX-SIGN` implements.

```sh
seed=$(python3 -c "print(bytes(range(48)).hex())")
openssl genpkey -algorithm SLH-DSA-SHAKE-128s -pkeyopt hexseed:$seed -out sk.pem
openssl pkey -in sk.pem -pubout -outform DER | tail -c 32 > shake-128s-seed-00-2f.pub
printf '\xde\xad' > msg.bin
openssl pkeyutl -sign -inkey sk.pem -in msg.bin -rawin \
    -pkeyopt deterministic:1 -pkeyopt message-encoding:0 \
    -out shake-128s-seed-00-2f-dead.sig
```

With `message-encoding:1`, OpenSSL signs through the standard's pure
interface, which hashes `00`, the context string's length, the context
string and then the message. A caller that wants such a signature from
`SPX-SIGN` builds that message itself.
