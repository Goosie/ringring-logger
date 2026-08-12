/// Produces the attestation carried by an envelope's `attest` tag as
/// `(type, payload)`. Fase 1 has a single implementation, [NoneAttest];
/// Cashu-stempels land here in fase 2 as a second implementation.
abstract class AttestProvider {
  (String type, String payload) createAttest();
}

class NoneAttest implements AttestProvider {
  @override
  (String, String) createAttest() => ('none', '');
}
