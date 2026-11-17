K9!
# SPDX-License-Identifier: MPL-2.0
# proof-profiles.k9.ncl — DRAFT. Proof profiles for Agda theory proofs, as data.
#
# Status: unratified proposal. Nothing here is policy. The normative source is
# metadatastician/standards 3-practice/PROOF-POLICY.adoc; where this file and
# that prose disagree, the prose governs.
#
# Shape follows 3-practice/proof-witness-grades.k9.ncl.
# Kennel: data only, never evaluated with effects.
{
  pedigree = {
    schema_version = "1.0.0",
    component_type = "proof-policy-data",
    security = {
      leash = 'Kennel,
      trust_level = "data-only",
      allow_network = false,
      allow_filesystem_write = false,
      allow_subprocess = false,
      capabilities = [],
    },
    metadata = {
      name = "proof-profiles",
      version = "0.1.0-draft",
      description = "Draft proof profiles for Agda theory proofs: the flags, the layer, the witness route and the highest Proof Witness Grade each profile can reach.",
    },
    side_effects = [],
  },

  config = {
    status = "unratified-draft",

    policy = {
      repository = "metadatastician/standards",
      path = "3-practice/PROOF-POLICY.adoc",
      sections = ["2.1", "8.2"],
    },

    # A profile is chosen by what the proof needs, never by its field.
    profiles = [
      {
        id = "agda-canonical",
        layer = "core",
        authority = "PROOF-POLICY §2.1 (adopted)",
        invocation = "agda --safe --without-K --cubical-compatible",
        importable_by = ["agda-canonical", "agda-cubical"],
        recheck_legs = ["rocq", "lean"],
        highest_grade = "PWG-1",
        review_required = false,
      },
      {
        id = "agda-cubical",
        layer = "cubical",
        authority = "PROOF-POLICY §2.1 requires a separately reviewed proof profile; this entry is that profile in draft",
        invocation = "agda --safe --cubical",
        importable_by = ["agda-cubical"],
        may_import = ["agda-canonical"],
        # Legs attach to the statements of the canonical core, not to this layer.
        recheck_legs = [],
        highest_grade = "PWG-3",
        review_required = true,
        trusted_base_note = "reaches Agda.Primitive.Cubical and Agda.Builtin.Cubical.*; the §8.4 postulate list is longer and must be earned per prover pin",
      },
    ],

    # Stricter repository-level configurations. Named so they can be recorded;
    # TRUSTED-BASE-REDUCTION-POLICY says their extra flags are not a rule.
    repository_variants = [
      {
        id = "agda-canonical+builtin-only",
        extends = "agda-canonical",
        extra_flags = ["--double-check", "--ignore-interfaces", "-W error"],
        condition = "the development imports no library",
        seen_in = "JuliaPackageSpitter.jl, as described in docs/TRUSTED-BASE-REDUCTION-POLICY.adoc",
      },
    ],

    # What the proof needs decides the profile. First matching row wins.
    choose_by_need = [
      { need = "univalence, higher inductive types, or computing with paths", profile = "agda-cubical", rule = "put only the part that needs it in the cubical layer" },
      { need = "function extensionality as a theorem", profile = "agda-cubical", rule = "or keep the canonical core and carry extensionality as an explicit hypothesis" },
      { need = "axiom K or uniqueness of identity proofs", profile = "none", rule = "not admissible; restate over a type with decidable equality or carry an explicit set-level hypothesis" },
      { need = "a classical axiom (excluded middle, choice)", profile = "agda-canonical", rule = "PROVEN-WITH-AXIOMS under TRUSTED-BASE-REDUCTION-POLICY disposition (c)" },
      { need = "none of the above", profile = "agda-canonical", rule = "the default" },
    ],

    rules = {
      core_first = true,
      legs_attach_to_core_statements = true,
      cubical_only_statement_max_grade = "PWG-3",
      field_is_not_a_selector = true,
    },
  },
}
