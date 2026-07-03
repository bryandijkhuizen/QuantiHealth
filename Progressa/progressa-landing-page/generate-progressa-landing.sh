#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="progressa-landing"

echo "==> Creating Next.js landing project: ${PROJECT_NAME}"

# 1) Create Next.js app (App Router) with TS
npx create-next-app@latest "$PROJECT_NAME" \
  --ts \
  --app \
  --eslint \
  --src-dir false \
  --import-alias "@/*" \
  --no-tailwind

cd "$PROJECT_NAME"

echo "==> Creating folders"
mkdir -p app components public

echo "==> Writing files"

# package.json (overwrite to match lightweight config)
cat > package.json <<'JSON'
{
  "name": "progressa-landing",
  "private": true,
  "version": "1.0.0",
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint"
  },
  "dependencies": {
    "next": "^14.2.0",
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "@types/node": "^20.11.30",
    "@types/react": "^18.2.66",
    "@types/react-dom": "^18.2.22",
    "typescript": "^5.4.5"
  }
}
JSON

cat > next.config.js <<'JS'
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true
};

module.exports = nextConfig;
JS

cat > netlify.toml <<'TOML'
[build]
  command = "npm run build"
  publish = ".next"

[[plugins]]
  package = "@netlify/plugin-nextjs"
TOML

cat > app/layout.tsx <<'TSX'
import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://progressa.app"),
  title: "Progressa — Train smarter. Track better.",
  description:
    "Progressa is a light, modern fitness tracker for workouts, progress and consistency — designed to feel calm, fast and premium.",
  openGraph: {
    title: "Progressa — Train smarter. Track better.",
    description:
      "A calm, fast fitness tracker for workouts, progress and consistency.",
    type: "website",
    url: "https://progressa.app"
    // images: ["/og.png"]
  },
  twitter: {
    card: "summary_large_image",
    title: "Progressa — Train smarter. Track better.",
    description:
      "A calm, fast fitness tracker for workouts, progress and consistency."
    // images: ["/og.png"]
  },
  icons: {
    icon: "/favicon.ico"
  }
};

export default function RootLayout({
  children
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
TSX

cat > app/globals.css <<'CSS'
:root {
  --bg: #0b0d12;
  --card: rgba(255, 255, 255, 0.06);
  --card2: rgba(255, 255, 255, 0.08);
  --stroke: rgba(255, 255, 255, 0.12);
  --text: rgba(255, 255, 255, 0.92);
  --muted: rgba(255, 255, 255, 0.68);
  --muted2: rgba(255, 255, 255, 0.54);

  --accent: #7c5cff;
  --accent2: #2ee59d;

  --shadow: 0 10px 35px rgba(0, 0, 0, 0.35);
  --radius: 20px;
}

* { box-sizing: border-box; }

html,
body {
  padding: 0;
  margin: 0;
  background:
    radial-gradient(1200px 700px at 20% 10%, rgba(124, 92, 255, 0.18), transparent 60%),
    radial-gradient(900px 650px at 90% 20%, rgba(46, 229, 157, 0.14), transparent 55%),
    var(--bg);
  color: var(--text);
  font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica,
    Arial, "Apple Color Emoji", "Segoe UI Emoji";
  line-height: 1.35;
}

a { color: inherit; text-decoration: none; }
::selection { background: rgba(124, 92, 255, 0.35); }

.container {
  max-width: 1100px;
  margin: 0 auto;
  padding: 0 20px;
}

.hr {
  height: 1px;
  background: linear-gradient(90deg, transparent, var(--stroke), transparent);
  border: 0;
  margin: 36px 0;
}

.pill {
  display: inline-flex;
  gap: 10px;
  align-items: center;
  padding: 8px 12px;
  border: 1px solid var(--stroke);
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.04);
  color: var(--muted);
  font-size: 13px;
}

.card {
  border: 1px solid var(--stroke);
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.06), rgba(255, 255, 255, 0.03));
  border-radius: var(--radius);
  box-shadow: var(--shadow);
}

.btnRow {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
}

.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 12px 16px;
  border-radius: 14px;
  border: 1px solid var(--stroke);
  background: rgba(255, 255, 255, 0.04);
  color: var(--text);
  font-weight: 600;
  letter-spacing: 0.2px;
  transition: transform 120ms ease, background 120ms ease, border 120ms ease;
}

.btn:hover {
  transform: translateY(-1px);
  background: rgba(255, 255, 255, 0.06);
  border-color: rgba(255, 255, 255, 0.16);
}

.btnPrimary {
  border: 1px solid rgba(124, 92, 255, 0.55);
  background: linear-gradient(135deg, rgba(124, 92, 255, 0.9), rgba(46, 229, 157, 0.7));
  color: #0b0d12;
}

.btnPrimary:hover {
  transform: translateY(-1px) scale(1.01);
}

.grid { display: grid; gap: 14px; }

@media (min-width: 900px) {
  .grid3 { grid-template-columns: repeat(3, 1fr); }
  .grid2 { grid-template-columns: repeat(2, 1fr); }
}

.muted { color: var(--muted); }
.small { color: var(--muted2); font-size: 13px; }

.h1 {
  font-size: 46px;
  line-height: 1.05;
  letter-spacing: -1px;
  margin: 14px 0 10px;
}

@media (max-width: 520px) { .h1 { font-size: 38px; } }

.h2 { font-size: 22px; margin: 0 0 8px; }

.hero { padding: 56px 0 28px; }

.heroWrap {
  display: grid;
  gap: 18px;
  padding: 22px;
}

@media (min-width: 900px) {
  .heroWrap {
    grid-template-columns: 1.25fr 0.75fr;
    align-items: center;
    padding: 26px;
  }
}

.heroMock {
  padding: 18px;
  overflow: hidden;
  position: relative;
}

.mockTop {
  display: flex;
  gap: 8px;
  align-items: center;
  margin-bottom: 14px;
}

.dot {
  width: 10px;
  height: 10px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.18);
}

.mockChart {
  height: 170px;
  border-radius: 16px;
  border: 1px solid var(--stroke);
  background:
    radial-gradient(400px 200px at 20% 30%, rgba(124, 92, 255, 0.18), transparent 55%),
    radial-gradient(350px 220px at 80% 45%, rgba(46, 229, 157, 0.14), transparent 55%),
    rgba(255, 255, 255, 0.03);
  position: relative;
}

.mockLine {
  position: absolute;
  inset: 0;
  background:
    linear-gradient(transparent 68%, rgba(255, 255, 255, 0.08) 69%, transparent 70%),
    linear-gradient(90deg, transparent 28%, rgba(255, 255, 255, 0.08) 29%, transparent 30%),
    linear-gradient(135deg, rgba(124, 92, 255, 0.0), rgba(124, 92, 255, 0.25));
  mask-image: radial-gradient(circle at 30% 30%, black 40%, transparent 70%);
}

.kpis {
  margin-top: 14px;
  display: grid;
  gap: 10px;
}

.kpi {
  padding: 12px 12px;
  border-radius: 16px;
  border: 1px solid var(--stroke);
  background: rgba(255, 255, 255, 0.03);
}

.kpiLabel { font-size: 12px; color: var(--muted2); }
.kpiValue { font-size: 18px; margin-top: 4px; font-weight: 700; }

.section { padding: 26px 0; }
.featureCard { padding: 16px; }

.icon {
  width: 36px;
  height: 36px;
  border-radius: 12px;
  border: 1px solid var(--stroke);
  background: rgba(255, 255, 255, 0.04);
  display: grid;
  place-items: center;
  margin-bottom: 10px;
}

.footer { padding: 28px 0 40px; color: var(--muted2); font-size: 13px; }

.nav {
  padding: 18px 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.navLinks { display: flex; gap: 14px; align-items: center; }

.badge {
  font-size: 12px;
  color: var(--muted);
  border: 1px solid var(--stroke);
  padding: 6px 10px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.03);
}
CSS

cat > components/Container.tsx <<'TSX'
export default function Container({ children }: { children: React.ReactNode }) {
  return <div className="container">{children}</div>;
}
TSX

cat > components/Logo.tsx <<'TSX'
export default function Logo() {
  return (
    <div style={{ display: "inline-flex", alignItems: "center", gap: 10 }}>
      <div
        aria-hidden
        style={{
          width: 32,
          height: 32,
          borderRadius: 12,
          background:
            "linear-gradient(135deg, rgba(124,92,255,0.95), rgba(46,229,157,0.8))",
          boxShadow: "0 10px 25px rgba(0,0,0,0.25)",
          border: "1px solid rgba(255,255,255,0.18)"
        }}
      />
      <div style={{ fontWeight: 800, letterSpacing: -0.4 }}>Progressa</div>
    </div>
  );
}
TSX

cat > components/Section.tsx <<'TSX'
export default function Section({
  id,
  title,
  subtitle,
  children
}: {
  id?: string;
  title: string;
  subtitle?: string;
  children: React.ReactNode;
}) {
  return (
    <section id={id} className="section">
      <div style={{ marginBottom: 14 }}>
        <div className="h2">{title}</div>
        {subtitle ? <div className="muted">{subtitle}</div> : null}
      </div>
      {children}
    </section>
  );
}
TSX

cat > app/page.tsx <<'TSX'
import Container from "@/components/Container";
import Logo from "@/components/Logo";
import Section from "@/components/Section";

function Icon({ label }: { label: string }) {
  return (
    <div className="icon" aria-label={label} title={label}>
      <span style={{ fontSize: 16, opacity: 0.92 }}>✦</span>
    </div>
  );
}

export default function Page() {
  return (
    <>
      <header>
        <Container>
          <div className="nav">
            <a href="#" aria-label="Progressa home">
              <Logo />
            </a>

            <nav className="navLinks" aria-label="Primary">
              <a className="badge" href="#features">
                Features
              </a>
              <a className="badge" href="#faq">
                FAQ
              </a>
              <a className="btn btnPrimary" href="#cta">
                Get Progressa
              </a>
            </nav>
          </div>
        </Container>
      </header>

      <main>
        <section className="hero">
          <Container>
            <div className="heroWrap card">
              <div style={{ padding: 6 }}>
                <div className="pill">
                  <span aria-hidden>⚡</span>
                  <span>Lightweight, calm, premium fitness tracking</span>
                </div>

                <h1 className="h1">
                  Train smarter.
                  <br />
                  Track better.
                  <br />
                  Stay consistent.
                </h1>

                <p className="muted" style={{ fontSize: 16, margin: "0 0 16px" }}>
                  Progressa helps you log workouts, follow your progress, and build
                  momentum—without clutter. Fast UI, clean insights, and a “just
                  works” feel.
                </p>

                <div className="btnRow">
                  <a className="btn btnPrimary" href="#cta">
                    Join the waitlist
                  </a>
                  <a className="btn" href="#features">
                    See features
                  </a>
                </div>

                <div className="small" style={{ marginTop: 12 }}>
                  No spam. One email when we launch. Unsubscribe anytime.
                </div>
              </div>

              <div className="heroMock card">
                <div className="mockTop">
                  <div className="dot" />
                  <div className="dot" />
                  <div className="dot" />
                  <div className="small" style={{ marginLeft: 8 }}>
                    Progress overview
                  </div>
                </div>

                <div className="mockChart">
                  <div className="mockLine" />
                </div>

                <div className="kpis">
                  <div className="kpi">
                    <div className="kpiLabel">Last workout</div>
                    <div className="kpiValue">Upper — 42 min</div>
                  </div>
                  <div className="kpi">
                    <div className="kpiLabel">This week</div>
                    <div className="kpiValue">3 sessions</div>
                  </div>
                </div>
              </div>
            </div>
          </Container>
        </section>

        <Container>
          <hr className="hr" />

          <Section
            id="features"
            title="What you get"
            subtitle="Everything you need for progress—nothing you don’t."
          >
            <div className="grid grid3">
              <div className="featureCard card">
                <Icon label="Fast logging" />
                <div className="h2">Fast logging</div>
                <div className="muted">
                  Log sets quickly with a calm interface. Stay in the flow during
                  your workout.
                </div>
              </div>

              <div className="featureCard card">
                <Icon label="Progress insights" />
                <div className="h2">Progress insights</div>
                <div className="muted">
                  Simple charts and trends that actually help you make decisions.
                </div>
              </div>

              <div className="featureCard card">
                <Icon label="Consistency" />
                <div className="h2">Consistency</div>
                <div className="muted">
                  Gentle nudges and reminders that fit your routine—without being
                  annoying.
                </div>
              </div>
            </div>
          </Section>

          <Section
            title="Designed to feel premium"
            subtitle="Light on your phone. Heavy on results."
          >
            <div className="grid grid2">
              <div className="featureCard card">
                <div className="h2">Clean by default</div>
                <div className="muted">
                  A layout that feels like iOS—glass, spacing, and typography that
                  stays out of your way.
                </div>
              </div>
              <div className="featureCard card">
                <div className="h2">Built for speed</div>
                <div className="muted">
                  Lightweight UI and straightforward navigation so everything opens
                  instantly.
                </div>
              </div>
            </div>
          </Section>

          <Section
            id="faq"
            title="FAQ"
            subtitle="Short answers. No marketing fluff."
          >
            <div className="grid grid2">
              <div className="featureCard card">
                <div className="h2">Is Progressa free?</div>
                <div className="muted">
                  There will be a solid free tier, with a Pro plan for advanced
                  features.
                </div>
              </div>
              <div className="featureCard card">
                <div className="h2">When is the launch?</div>
                <div className="muted">
                  Soon. Join the waitlist and you’ll be the first to know.
                </div>
              </div>
              <div className="featureCard card">
                <div className="h2">iOS or Android?</div>
                <div className="muted">
                  Starting with iOS, expanding from there based on demand.
                </div>
              </div>
              <div className="featureCard card">
                <div className="h2">Can I import workouts?</div>
                <div className="muted">
                  Import is on the roadmap—especially if you already track
                  consistently elsewhere.
                </div>
              </div>
            </div>
          </Section>

          <Section
            id="cta"
            title="Get early access"
            subtitle="Drop your email and we’ll notify you when Progressa opens up."
          >
            <div className="card" style={{ padding: 16 }}>
              <form
                name="waitlist"
                method="POST"
                data-netlify="true"
                style={{ display: "grid", gap: 10 }}
              >
                <input type="hidden" name="form-name" value="waitlist" />

                <label className="small" htmlFor="email">
                  Email
                </label>
                <input
                  id="email"
                  name="email"
                  type="email"
                  required
                  placeholder="you@domain.com"
                  style={{
                    padding: "12px 14px",
                    borderRadius: 14,
                    border: "1px solid rgba(255,255,255,0.14)",
                    background: "rgba(255,255,255,0.04)",
                    color: "rgba(255,255,255,0.92)",
                    outline: "none"
                  }}
                />

                <div className="btnRow" style={{ marginTop: 4 }}>
                  <button className="btn btnPrimary" type="submit">
                    Join waitlist
                  </button>
                  <a className="btn" href="#features">
                    Back to features
                  </a>
                </div>

                <div className="small">
                  By joining, you agree we can email you about Progressa. That’s it.
                </div>
              </form>
            </div>
          </Section>

          <footer className="footer">
            <div
              style={{
                display: "flex",
                flexWrap: "wrap",
                gap: 10,
                justifyContent: "space-between"
              }}
            >
              <div>© {new Date().getFullYear()} Progressa</div>
              <div style={{ display: "flex", gap: 12 }}>
                <a className="badge" href="#faq">
                  FAQ
                </a>
                <a className="badge" href="mailto:hello@progressa.app">
                  Contact
                </a>
              </div>
            </div>
          </footer>
        </Container>
      </main>
    </>
  );
}
TSX

cat > app/robots.ts <<'TSX'
import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [{ userAgent: "*", allow: "/" }],
    sitemap: "https://progressa.app/sitemap.xml"
  };
}
TSX

cat > app/sitemap.ts <<'TSX'
import type { MetadataRoute } from "next";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: "https://progressa.app/",
      lastModified: new Date()
    }
  ];
}
TSX

# Optional: keep public dir non-empty (Netlify sometimes fine either way)
touch public/.gitkeep

echo "==> Installing dependencies"
npm install

echo "==> Done!"
echo ""
echo "Next steps:"
echo "  cd ${PROJECT_NAME}"
echo "  npm run dev"
echo ""
echo "Netlify:"
echo "  - netlify.toml included"
echo "  - Push to GitHub and import in Netlify"
