import { Github, Mail } from 'lucide-react'

export function FooterSection() {
  return (
    <footer className="py-12 border-t border-white/10">
      <div className="container mx-auto px-4">
        <div className="flex flex-col md:flex-row items-center justify-between gap-6">
          {/* Brand */}
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center">
              <span className="text-white text-xs font-bold">P</span>
            </div>
            <div>
              <p className="text-white font-semibold text-sm">Piper</p>
              <p className="text-white/40 text-xs">© 2026 Team докер навозник. Хакатон-проект.</p>
            </div>
          </div>

          {/* Links */}
          <div className="flex items-center gap-6">
            <a
              href="https://github.com/tuhlopuz1/piper"
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-2 text-white/50 hover:text-white transition-colors text-sm"
            >
              <Github className="w-4 h-4" />
              GitHub
            </a>
            <a
              href="vickz.ru"
              className="flex items-center gap-2 text-white/50 hover:text-white transition-colors text-sm"
            >
              <Mail className="w-4 h-4" />
              Контакт
            </a>
          </div>
        </div>
      </div>
    </footer>
  )
}
