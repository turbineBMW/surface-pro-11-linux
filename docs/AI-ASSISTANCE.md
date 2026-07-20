# AI-assisted development disclosure

AI tools materially assisted this experimental project. The maintainer reports
using Fable 5 and ChatGPT 5.6 during the original hardware investigation and
driver development. Later source separation, provenance cleanup, build
automation, documentation, static review, and bounded hardware validation were
assisted by Codex based on GPT-5.

The tools were used to interpret maintainer-supplied runtime observations,
suggest Linux implementations, review diffs, generate or revise scripts and
documentation, and organize validation. They had no NDA access, private vendor
source, confidential specification, or proprietary repository access. Inputs
relevant to the published implementation were public open-source code, public
specifications, Linux interfaces, and runtime behavior observed on hardware
owned by the maintainer.

AI output was treated as untrusted draft material. The publication candidate
was rebuilt, schema-checked, statically audited, reconstructed from its public
patches and bundles, and tested on the target hardware. Those checks reduce
technical and provenance risk but do not establish authorship of model training
data, provide legal advice, or guarantee that a third party will not make a
claim.

No AI system may add a human `Signed-off-by`, `Reviewed-by`, or `Tested-by`
trailer. If patches are later proposed upstream, the human submitter must first
review and understand each change, personally certify the Developer Certificate
of Origin where applicable, and use the disclosure format requested by the
target subsystem at that time.
