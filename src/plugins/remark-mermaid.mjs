import { visit } from 'unist-util-visit';

function escapeHtml(value) {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export function remarkMermaid() {
  return (tree) => {
    visit(tree, 'code', (node, index, parent) => {
      if (node.lang !== 'mermaid' || !parent || typeof index !== 'number') return;
      parent.children[index] = {
        type: 'html',
        value: `<div class="mermaid-wrapper"><pre class="mermaid" data-mermaid-src="${escapeHtml(node.value)}">${escapeHtml(node.value)}</pre></div>`,
      };
    });
  };
}
