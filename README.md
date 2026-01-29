# ComfyUI on Google Colab

Run ComfyUI on Google Colab with one command.

## Installation

```python
from google.colab import drive
drive.mount('/content/drive')

!curl -sSL https://cross-entropy-ai.github.io/colab-comfyui/install.sh | bash
```

After installation, you'll get a public URL to access ComfyUI.
