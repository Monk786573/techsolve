import { useEffect, useRef, useState, type FormEvent } from "react";
import { createFileRoute } from "@tanstack/react-router";

import { Button } from "@/components/ui/button";

const categories = [
  { mark: "</>", name: "Programming", description: "Language quirks, build errors and logic that won’t cooperate." },
  { mark: "WEB", name: "Web Development", description: "Frontend, backend, hosting and everything between." },
  { mark: "AI", name: "AI/ML", description: "Training runs, inference bugs and data pipelines." },
  { mark: "HW", name: "Hardware", description: "Boards, sensors, power rails and silicon mysteries." },
  { mark: "NET", name: "Networking", description: "Routing, DNS, VPNs and packets that vanish." },
  { mark: "SEC", name: "Cybersecurity", description: "Hardening, incident response and safe defaults." },
  { mark: "AND", name: "Android", description: "SDK issues, device quirks and Gradle pain." },
  { mark: "OS", name: "Operating Systems", description: "Kernels, drivers, shells and updates gone sideways." },
  { mark: "CLOUD", name: "Cloud", description: "Deployments, infrastructure and services that scale." },
  { mark: "DB", name: "Databases", description: "Queries, schemas, migrations and data reliability." },
  { mark: "CAREER", name: "Career", description: "Technical interviews, growth and finding your next step." },
];

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "TECHSOLVE — Every tech problem has a solution" },
      {
        name: "description",
        content: "Share a technical problem, learn from people who have solved it, and keep the answer useful for the next person.",
      },
      { property: "og:title", content: "TECHSOLVE — Every tech problem has a solution" },
      {
        property: "og:description",
        content: "A community for technical problems, practical answers and the fixes worth keeping.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: Index,
});

type Message = { text: string; kind: "bot" | "user" };

function TechCanvas() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const context = canvas?.getContext("2d");
    if (!canvas || !context) return;

    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const points = Array.from({ length: 78 }, () => ({
      x: Math.random(),
      y: Math.random(),
      z: Math.random(),
      phase: Math.random() * Math.PI * 2,
    }));
    let frame = 0;
    let pointerX = 0;
    let pointerY = 0;
    let width = 0;
    let height = 0;

    const resize = () => {
      const ratio = Math.min(window.devicePixelRatio || 1, 2);
      width = window.innerWidth;
      height = window.innerHeight;
      canvas.width = width * ratio;
      canvas.height = height * ratio;
      context.setTransform(ratio, 0, 0, ratio, 0, 0);
      draw(0);
    };

    const onPointerMove = (event: PointerEvent) => {
      pointerX = event.clientX / Math.max(width, 1) - 0.5;
      pointerY = event.clientY / Math.max(height, 1) - 0.5;
    };

    const draw = (time: number) => {
      if (!context || width === 0 || height === 0) return;
      context.clearRect(0, 0, width, height);
      const scale = Math.min(width, height);
      const centerX = width * (width < 900 ? 0.78 : 0.77) + pointerX * 16;
      const centerY = height * 0.35 + pointerY * 12;
      const rotation = time * 0.00008;

      for (let ring = 0; ring < 3; ring += 1) {
        context.beginPath();
        context.ellipse(centerX, centerY, scale * (0.2 + ring * 0.052), scale * (0.066 + ring * 0.018), rotation + ring * 0.8, 0, Math.PI * 2);
        context.strokeStyle = ring === 0 ? "oklch(0.86 0.22 135 / 0.3)" : "oklch(0.98 0 0 / 0.11)";
        context.lineWidth = 1;
        context.stroke();
      }

      const projected = points.map((point, index) => {
        const angle = point.phase + rotation * (index % 2 === 0 ? 1 : -1);
        const radius = scale * (0.08 + point.z * 0.3);
        return {
          x: centerX + Math.cos(angle + point.x * 2) * radius,
          y: centerY + Math.sin(angle + point.y * 2) * radius * 0.55,
          alpha: 0.12 + point.z * 0.38,
        };
      });

      for (let index = 0; index < projected.length; index += 1) {
        const point = projected[index];
        if (!point) continue;
        for (let neighbor = index + 1; neighbor < projected.length; neighbor += 1) {
          const other = projected[neighbor];
          if (!other) continue;
          const distance = Math.hypot(point.x - other.x, point.y - other.y);
          if (distance < scale * 0.07) {
            context.beginPath();
            context.moveTo(point.x, point.y);
            context.lineTo(other.x, other.y);
            context.strokeStyle = `oklch(0.86 0.22 135 / ${0.12 * (1 - distance / (scale * 0.07))})`;
            context.stroke();
          }
        }
        context.beginPath();
        context.arc(point.x, point.y, point.alpha * 2, 0, Math.PI * 2);
        context.fillStyle = `oklch(0.86 0.22 135 / ${point.alpha})`;
        context.fill();
      }
    };

    const animate = (now: number) => {
      draw(now);
      if (!reduceMotion) frame = window.requestAnimationFrame(animate);
    };

    resize();
    if (!reduceMotion) frame = window.requestAnimationFrame(animate);
    window.addEventListener("resize", resize);
    window.addEventListener("pointermove", onPointerMove, { passive: true });
    return () => {
      window.cancelAnimationFrame(frame);
      window.removeEventListener("resize", resize);
      window.removeEventListener("pointermove", onPointerMove);
    };
  }, []);

  return <canvas aria-hidden="true" className="tech-canvas" ref={canvasRef} />;
}

function Index() {
  const [messages, setMessages] = useState<Message[]>([
    {
      kind: "bot",
      text: "Welcome to TechSolve. Describe your technical issue and include your device or environment, software version, exact error, and what you expected to happen.\n\nI’ll aim to return a complete solution in one response: diagnosis, fix, and verification.",
    },
  ]);
  const [prompt, setPrompt] = useState("");

  const submitPrompt = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const question = prompt.trim();
    if (!question) return;
    setMessages((current) => [
      ...current,
      { kind: "user", text: question },
      {
        kind: "bot",
        text: "The assistant interface is ready, but the Anthropic backend is not connected in this preview, so your message has not been sent to an AI model.\n\nWhen connected, the response will be structured as:\n1. Likely root cause\n2. Recommended solution\n3. Step-by-step implementation\n4. Verification and fallback checks",
      },
    ]);
    setPrompt("");
  };

  return (
    <div className="tech-page">
      <TechCanvas />
      <header className="tech-header">
        <nav className="tech-nav" aria-label="Main navigation">
          <a className="tech-brand" href="#top" aria-label="TECHSOLVE home">
            <svg aria-hidden="true" width="30" height="30" viewBox="0 0 30 30" fill="none" stroke="currentColor" strokeWidth="1.8">
              <path d="m15 2.5 11 6.3v12.4L15 27.5 4 21.2V8.8z" />
              <path d="m15 9 5.5 3.2v6.4L15 21.8l-5.5-3.2v-6.4z" />
            </svg>
            <span>TECHSOLVE</span>
          </a>
          <div className="tech-links">
            <a href="#categories">Categories</a>
            <a href="#how">How it works</a>
            <a href="#assistant">AI Assistant</a>
            <a href="#soon">Contact</a>
          </div>
          <a className="tech-button tech-button-primary tech-nav-cta" href="#assistant">Ask TechSolve <span aria-hidden="true">↗</span></a>
        </nav>
      </header>

      <main>
        <section className="tech-section tech-top" id="top">
          <div className="tech-hero-copy">
            <div className="tech-status"><span className="tech-status-dot" />Community platform in development</div>
            <h1><span className="tech-accent-text">Every tech problem</span> has a solution.</h1>
            <p className="tech-lead">Share a technical problem, talk it through with people who’ve fixed it before, and keep the answer for the next person who gets stuck.</p>
            <div className="tech-hero-actions">
              <a className="tech-button tech-button-primary" href="#categories">Explore categories</a>
              <a className="tech-button tech-button-secondary" href="#how">See how it works</a>
            </div>
          </div>
          <div className="tech-hero-index" aria-hidden="true"><span>COMMUNITY / 01</span><span>11 FIELDS · ONE COMMUNITY</span></div>
        </section>

        <section className="tech-section tech-categories" id="categories">
          <div className="tech-section-heading">
            <div><p className="tech-eyebrow">A PLACE FOR EVERY FIX</p><h2>Pick your corner of tech</h2></div>
            <p className="tech-sub">Eleven fields, one community. Find the people who know your problem.</p>
          </div>
          <div className="tech-grid">
            {categories.map((category, index) => (
              <article className="tech-category" key={category.name}>
                <span className="tech-category-index">{String(index + 1).padStart(2, "0")}</span>
                <div className="tech-icon" aria-hidden="true">{category.mark}</div>
                <h3>{category.name}</h3>
                <p>{category.description}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="tech-section tech-how" id="how">
          <div className="tech-solution-card" aria-label="Example of a problem and its accepted solution">
            <div className="tech-solution-topline"><span>NETWORKING / 01</span><span className="tech-solved-pill"><span aria-hidden="true">✓</span> SOLVED</span></div>
            <h3>Server returns 502 after deploy</h3>
            <p>upstream prematurely closed connection</p>
            <div className="tech-answer"><span>ACCEPTED ANSWER</span><strong>Raise the proxy timeout</strong><code>proxy_read_timeout 120s;</code></div>
          </div>
          <div className="tech-how-copy">
            <p className="tech-eyebrow">A FIX THAT STICKS</p>
            <h2>From stuck<br />to solved</h2>
            <p className="tech-sub">Every problem starts open. When an answer works, its author marks it solved, and the fix stays easy to find.</p>
            <ol className="tech-steps">
              <li><strong>Share the problem</strong><span>Describe what broke and what you tried.</span></li>
              <li><strong>Discuss it</strong><span>Others ask questions and suggest fixes.</span></li>
              <li><strong>Mark it solved</strong><span>The working answer is pinned for everyone.</span></li>
            </ol>
          </div>
        </section>

        <section className="tech-section tech-assistant" id="assistant">
          <div className="tech-assistant-copy">
            <p className="tech-eyebrow">03 / TECHSOLVE INTELLIGENCE</p>
            <h2>Bring the problem.<br /><span className="tech-accent-text">Leave with a plan.</span></h2>
            <p className="tech-sub">A technical problem-solving assistant built to reason through the issue, identify the likely root cause, and give you a practical first-pass solution — not a pile of generic suggestions.</p>
            <ul className="tech-points">
              <li><span>✳</span><p><strong>Root-cause first</strong>Understand why the issue is happening before applying a fix.</p></li>
              <li><span>↳</span><p><strong>Actionable steps</strong>Clear ordered instructions, with code examples when relevant.</p></li>
              <li><span>✓</span><p><strong>Verification included</strong>Know how to confirm the fix worked and what to check next.</p></li>
            </ul>
            <p className="tech-preview-note">AI PROVIDER: ANTHROPIC · SERVER CONNECTION PENDING</p>
          </div>
          <div className="tech-assistant-panel">
            <div className="tech-assistant-head">
              <span className="tech-assistant-title"><span className="tech-assistant-symbol">⌘</span> TECHSOLVE / AI ASSISTANT</span>
              <span className="tech-assistant-state">PREVIEW MODE</span>
            </div>
            <div className="tech-messages" aria-live="polite">
              {messages.map((message, index) => <div className={`tech-message tech-message-${message.kind}`} key={`${message.kind}-${index}`}>{message.text}</div>)}
            </div>
            <div className="tech-suggestions" aria-label="Example prompts">
              {["Help me debug a Python error.", "Help me diagnose a PC hardware issue.", "Help me fix a website issue."].map((suggestion) => (
                <Button className="tech-suggestion" key={suggestion} onClick={() => setPrompt(suggestion)} size="sm" type="button" variant="outline">
                  {suggestion.startsWith("Help me debug") ? "Python error" : suggestion.startsWith("Help me diagnose") ? "PC / hardware" : "Web development"}
                </Button>
              ))}
            </div>
            <p className="tech-ai-warning">Preview only — no AI request is sent yet. Never enter passwords, API keys, or private information.</p>
            <form className="tech-ai-form" onSubmit={submitPrompt}>
              <input aria-label="Describe your technical problem" autoComplete="off" maxLength={1200} onChange={(event) => setPrompt(event.target.value)} placeholder="Describe your technical problem…" value={prompt} />
              <Button aria-label="Send message" className="tech-send-button" disabled={!prompt.trim()} type="submit">Send <span aria-hidden="true">↗</span></Button>
            </form>
          </div>
        </section>

        <section className="tech-section tech-contact" id="soon">
          <p className="tech-eyebrow">THE NEXT CHAPTER</p>
          <h2>COMING SOON</h2>
          <p className="tech-sub">For enquiries about site work, email me:</p>
          <a className="tech-mail" href="mailto:himonktech@gmail.com">himonktech@gmail.com</a>
        </section>
      </main>
      <footer className="tech-footer">© 2026 TECHSOLVE. Prototype preview; sample content only.</footer>
    </div>
  );
}