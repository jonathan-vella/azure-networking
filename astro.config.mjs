import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { remarkMermaid } from './src/plugins/remark-mermaid.mjs';

export default defineConfig({
  site: 'https://jonathan-vella.github.io',
  base: '/azure-networking',
  markdown: {
    remarkPlugins: [remarkMermaid],
  },
  integrations: [
    starlight({
      title: 'Azure Networking Handbook',
      description:
        'An opinionated Field Architect Handbook for designing, securing, validating, and operating enterprise Azure networks.',
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/jonathan-vella/azure-networking',
        },
      ],
      editLink: {
        baseUrl: 'https://github.com/jonathan-vella/azure-networking/edit/main/',
      },
      customCss: ['./src/styles/custom.css'],
      components: {
        Head: './src/components/Head.astro',
      },
      sidebar: [
        {
          label: 'Start Here',
          items: [{ label: 'Field Architect Roadmap', slug: 'index' }],
        },
        {
          label: '1. Foundations',
          autogenerate: { directory: '01-foundations' },
        },
        {
          label: '2. Core Topologies',
          autogenerate: { directory: '02-core-topologies' },
        },
        {
          label: '3. Hybrid Connectivity',
          autogenerate: { directory: '03-hybrid-connectivity' },
        },
        {
          label: '4. Network Security & Private Link',
          autogenerate: { directory: '04-network-security' },
        },
        {
          label: '5. Workload Networking',
          autogenerate: { directory: '05-workload-networking' },
        },
        {
          label: '6. Day-2 Ops, Reviews & Labs',
          autogenerate: { directory: '06-operations-reviews' },
        },
      ],
    }),
  ],
});
