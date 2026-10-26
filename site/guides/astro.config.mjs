import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://nextshot.dev',
  base: '/guides',
  trailingSlash: 'always',
  devToolbar: { enabled: false },
  integrations: [starlight({
    title: 'Nextshot Guides',
    description: 'Clear visual instructions. One complete handoff to your AI.',
    defaultLocale: 'root',
    locales: { root: { label: 'English', lang: 'en' } },
    disable404Route: false,
    favicon: '/nextshot-icon.png',
    head: [{ tag: 'meta', attrs: { name: 'robots', content: 'noindex, nofollow' } }],
    customCss: ['./src/styles/guides.css'],
    components: {
      Header: './src/components/Header.astro',
      ThemeSelect: './src/components/Empty.astro',
      Footer: './src/components/Footer.astro',
      PageTitle: './src/components/PageTitle.astro',
      Head: './src/components/Head.astro',
    },
    sidebar: [
      { label: 'Start here', items: [
        { label: 'Your first handoff', slug: 'first-handoff' },
        { label: 'Install Nextshot', slug: 'install' },
        { label: 'Connect your agent', slug: 'connect-agent' },
      ] },
      { label: 'Work with rounds', items: [
        { label: 'Multiple captures', slug: 'multiple-captures' },
        { label: 'Find and reuse work', slug: 'reuse-rounds' },
      ] },
      { label: 'Quick answers', items: [
        { label: 'Keyboard shortcuts', slug: 'shortcuts' },
        { label: 'Fix a problem', slug: 'troubleshooting' },
      ] },
    ],
    pagination: true,
    lastUpdated: false,
    social: [],
  })],
});
