import { useState, useEffect } from 'react'
import { motion } from 'framer-motion'
import { Button } from '@/components/ui/button'
import { Download, Menu, X } from 'lucide-react'

const links = [
  { label: 'Как работает', href: '#how-it-works' },
  { label: 'Возможности', href: '#features' },
  { label: 'Скриншоты', href: '#screenshots' },
  { label: 'FAQ', href: '#faq' },
]

export function Navbar() {
  const [scrolled, setScrolled] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)

  useEffect(() => {
    const handler = () => setScrolled(window.scrollY > 20)
    window.addEventListener('scroll', handler)
    return () => window.removeEventListener('scroll', handler)
  }, [])

  return (
    <motion.header
      initial={{ y: -80, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.5 }}
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        scrolled ? 'bg-black/60 backdrop-blur-xl border-b border-white/10' : 'bg-transparent'
      }`}
    >
      <div className="container mx-auto px-4 h-16 flex items-center justify-between">
        {/* Logo */}
        <a href="#" className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center shadow-md shadow-indigo-500/30">
            <span className="text-white text-sm font-bold">P</span>
          </div>
          <span className="text-white font-bold text-lg">Piper</span>
        </a>

        {/* Desktop nav */}
        <nav className="hidden md:flex items-center gap-6">
          {links.map((l) => (
            <a key={l.href} href={l.href} className="text-sm text-white/60 hover:text-white transition-colors">
              {l.label}
            </a>
          ))}
        </nav>

        {/* CTA */}
        <div className="hidden md:block">
          <a href="#download">
            <Button variant="gradient" size="sm" className="gap-2">
              <Download className="w-4 h-4" />
              Скачать
            </Button>
          </a>
        </div>

        {/* Mobile burger */}
        <button
          className="md:hidden text-white/70 hover:text-white"
          onClick={() => setMenuOpen(!menuOpen)}
        >
          {menuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
        </button>
      </div>

      {/* Mobile menu */}
      {menuOpen && (
        <motion.div
          initial={{ opacity: 0, height: 0 }}
          animate={{ opacity: 1, height: 'auto' }}
          exit={{ opacity: 0, height: 0 }}
          className="md:hidden bg-black/80 backdrop-blur-xl border-t border-white/10"
        >
          <div className="container mx-auto px-4 py-4 flex flex-col gap-3">
            {links.map((l) => (
              <a
                key={l.href}
                href={l.href}
                onClick={() => setMenuOpen(false)}
                className="text-white/70 hover:text-white py-2 text-sm transition-colors"
              >
                {l.label}
              </a>
            ))}
            <a href="#download" onClick={() => setMenuOpen(false)}>
              <Button variant="gradient" size="sm" className="gap-2 w-full mt-2">
                <Download className="w-4 h-4" />
                Скачать
              </Button>
            </a>
          </div>
        </motion.div>
      )}
    </motion.header>
  )
}
