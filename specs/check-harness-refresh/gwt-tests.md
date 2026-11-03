# gwt-tests — check-harness-refresh
spec: sha256 d90a1a4ef1cb95a0f37e8da40be2e39ad3bee3750be8f8aed2b2b23c98d353f4

## R0
R0.*: manual: goal-level

## TT1 — R1 — L2: D3, D2
run: bash skills/check-harness/tests/tt1_skill_name_test.sh
R1.1–R1.4: test: tt1_skill_name_test.sh (r1_1 … r1_4)

## TT2 — R2 — L2: D4, D5, D6, D2
run: bash skills/check-harness/tests/tt2_inventory_plugins_test.sh && bash skills/check-harness/tests/tt2_inventory_usage_test.sh && bash skills/check-harness/tests/tt2_inventory_sources_test.sh
R2.1, R2.2, R2.3, R2.9: test: tt2_inventory_plugins_test.sh · R2.5–R2.8: test: tt2_inventory_usage_test.sh · R2.4, R2.10, R2.11: test: tt2_inventory_sources_test.sh

## TT3 — R3 — L2: D7, D8, D2
run: bash skills/check-harness/tests/tt3_session_files_test.sh
R3.1–R3.7: test: tt3_session_files_test.sh

## TT4 — R4 — L2: D9, D3, D2
run: bash skills/check-harness/tests/tt4_session_metrics_test.sh
R4.1–R4.9: test: tt4_session_metrics_test.sh

## TT5 — R5 — L2: D12, D2
run: bash skills/check-harness/tests/tt5_project_root_test.sh
R5.1–R5.4: test: tt5_project_root_test.sh

## TT6 — R6 — L2: D14, D15, D18, D6, D2
run: bash skills/check-harness/tests/tt6_project_signals_test.sh && bash skills/check-harness/tests/tt6_project_signals_git_test.sh
R6.1, R6.2, R6.5, R6.6, R6.7: test: tt6_project_signals_test.sh · R6.3, R6.4, R6.8: test: tt6_project_signals_git_test.sh

## TT7–TT10 — R7–R10
every GWT: manual: spec-marked (no files)

## files (sha256 · blob)
- skills/check-harness/tests/tt1_skill_name_test.sh · 733355efeb36e8f53891635752e68de70e5ce588f19be4f9a49325afcdddc6ea · fd626e57447b82d43aaacff67eff45f7ee9bceba
- skills/check-harness/tests/tt2_inventory_plugins_test.sh · 6b9ffcddb60e638c68fe1f81dff3ba540d8d44e63bdb12e3ec852a39d3fc7283 · 3ecc5ca405446b0ecabede010c7d469329c7fdb5
- skills/check-harness/tests/tt2_inventory_sources_test.sh · 7dd75713cc0da9e0f650cb66533f06302386335ece68cf0fb69f59e1a8888f5b · 98efbc935244ffae1120533ab34f58613c0c86db
- skills/check-harness/tests/tt2_inventory_usage_test.sh · 7f94b543551943641e5e4f0f6f4607c4e74d371085d7f2183bf72c1bc8b33b03 · 565b1ee911febbb4ad896b9c74f95a64985a0823
- skills/check-harness/tests/tt3_session_files_test.sh · f0245d9b90b1cd94d9c7c6a02090f25f1c23c668f1e0e62422a66f29e3cdf647 · ccd0e81de2204b47a4069090e6ba41313ff0b19c
- skills/check-harness/tests/tt4_session_metrics_test.sh · 47b83d59fb1f144d05b8f5dd623fb448232a8f1b60d9bd3bbb08765499e22434 · 34d9f99cb1997cbbf1686d4b8135bebf9785b21e
- skills/check-harness/tests/tt5_project_root_test.sh · 8b0bf6ebb984cca5926e9e92ef9535907738748ec529d56143bb76214ec8c946 · e9f3ec38c0db261fef861ebc35ca72f847b3ebcf
- skills/check-harness/tests/tt6_project_signals_git_test.sh · 34916f61bdd23caffa9d643b906c146849d1f4cd8de7220d43350fff46133006 · ab750bdad901da6ad3f3b46fb851e53396e465f8
- skills/check-harness/tests/tt6_project_signals_test.sh · efbda31a8b3c5a4ff004de773e471a24556808a6d6f3f3ac279ffa03fa4f40f3 · aa5a01d5c0e469a35b3e1e7b98381595c851f811
