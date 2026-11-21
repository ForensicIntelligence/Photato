# Local diffusion runtime

| Package | Upstream revision | License |
| --- | --- | --- |
| GuernikaKit | [922f0c07b4456c2ef4e03fa21fdf4d6a3108623a](https://github.com/GuernikaCore/GuernikaKit/tree/922f0c07b4456c2ef4e03fa21fdf4d6a3108623a) | MIT |
| RandomGenerator | [660f57cd242919174169ed131b044e54f519c182](https://github.com/GuernikaCore/RandomGenerator/tree/660f57cd242919174169ed131b044e54f519c182) | Apache-2.0 |
| Schedulers | [64d2465deeb0df015658e1021e76bd40ba8c581c](https://github.com/GuernikaCore/Schedulers/tree/64d2465deeb0df015658e1021e76bd40ba8c581c) | Apache-2.0 |

Swift package manifests point to local dependencies and omit upstream test targets. GuernikaKit builds on [Apple’s MIT-licensed ML Stable Diffusion runtime](https://github.com/apple-aiml-research/ml-stable-diffusion/blob/5d8cdbb92dcc49ed5673799ee184eec357938d35/LICENSE.md). The application bundles [the runtime licenses and acknowledgements](LocalDiffusion-Licenses.txt). Model setup and terms are documented separately in [Local Generative Fill](../docs/LOCAL_GENERATIVE_FILL.md).
