# ComfyUI on Google Colab

Run ComfyUI on Google Colab with one command.

> [!NOTE]
> ComfyUI requires GPU/CUDA instance.


## Installation

```python
from google.colab import drive
drive.mount('/content/drive')

!curl -sSL https://cross-entropy-ai.github.io/colab-comfyui/install.sh | bash

from google.colab import output
output.eval_js('''
setInterval(()=>{
    console.log("keep alive");
    document.querySelector("colab-connect-button")?.click();
}, 60000);
''')
```

After installation, you'll get a public URL to access ComfyUI.
