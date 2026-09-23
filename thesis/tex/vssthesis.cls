%% vssthesis.cls (formerly srathesis.cls, formerly i4thesis.cls, formerly i7thesis.cls)
%%
%% Copyright (C) 2023      Jan S. Rellermeyer <rellermeyer@vss.uni-hannover.de>
%% Copyright (C) 2016-2019 Christian Dietrich <dietrich@sra.uni-hannover.de>
%% Copyright (C) 2009-2011 Christoph Sommer <christoph.sommer@informatik.uni-erlangen.de>
%%                         Falko Dressler
%
% License (pick one or both):
% - Creative Commons Attribution-Share Alike 3.0 (or later)
% - GPL v2 (or later)
%

\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{vssthesis}[2023/06/23 The VSS Thesis Class]  % YYYY/MM/DD

% -----------------------------------------------------------------------------
% Class options
% -----------------------------------------------------------------------------
\RequirePackage{ifthen}
\RequirePackage{iftex}

% Load at beginning, xcolor is used a lot in other packages
% We need it for lstset
\RequirePackage[dvipsnames]{xcolor}

% [germanthesis] - Thesis is written in German
\newboolean{germanthesis}
\setboolean{germanthesis}{false}
\DeclareOption{germanthesis}{\setboolean{germanthesis}{true}}

% [plainunnumbered] - Don't print numbers on plain pages
\newboolean{plainunnumbered}
\setboolean{plainunnumbered}{false}
\DeclareOption{plainunnumbered}{\setboolean{plainunnumbered}{true}}

% [watermark] - Print current time/date at bottom of each page
\newboolean{watermark}
\setboolean{watermark}{false}
\DeclareOption{watermark}{\setboolean{watermark}{true}}

% [twoside] - double sided
\newboolean{oneside}
\setboolean{oneside}{true}
\DeclareOption{twoside}{\setboolean{oneside}{false}}

% [privacy] - Generate a more privacy aware pdf
\newboolean{privacy}
\setboolean{privacy}{false}
\DeclareOption{privacy}{\setboolean{privacy}{true}}

\ProcessOptions \relax
% -----------------------------------------------------------------------------


% -----------------------------------------------------------------------------
% Basics
% -----------------------------------------------------------------------------
% This class is based on report
\ifthenelse{\boolean{oneside}}{
  \LoadClass[a4paper,10pt,onecolumn,oneside,openright]{report}
  \RequirePackage[
    a4paper,textwidth=410pt,textheight=598pt,
    bindingoffset=0cm,marginparwidth=3cm,
    hmarginratio=1:1,vmarginratio=1:1
  ]{geometry}
}{
\LoadClass[a4paper,10pt,onecolumn,twoside,openright]{report}
\RequirePackage[a4paper,textwidth=410pt,textheight=598pt,bindingoffset=0cm,marginparwidth=3cm,hmarginratio=1:1,vmarginratio=1:1]{geometry}
}
\ifthenelse{\boolean{germanthesis}}{
	\RequirePackage{parskip}
}{
	\setlength\parskip{0pt}
}

% 150 percent line spacing
\RequirePackage{setspace}

% Allow more (and larger) floats on text pages
\renewcommand{\topfraction}{0.9}  % use up to ..% of space on top
\renewcommand{\bottomfraction}{0.8}  % use up to ..% of space on bottom
\setcounter{topnumber}{4} % place up to .. on top
\setcounter{bottomnumber}{1} % place up to .. on bottom
\setcounter{totalnumber}{4} % place up to .. total
\renewcommand{\textfraction}{0.07} % allow down to ..% of text
\renewcommand{\floatpagefraction}{0.7} % fill at least ..% of float pages (must be less than \topfraction)

% Avoid widows and orphans (single line on bottom or top of page, respectively) at almost any cost
\clubpenalty = 10000
\widowpenalty = 10000
\displaywidowpenalty = 10000 % formulas
%\raggedbottom

% Default fonts
\newcommand{\mypageheadfont}{\normalfont}
\newcommand{\myheadingfont}{\normalfont}
\RequirePackage[bitstream-charter]{mathdesign} % RM: Bitstream Charter
\linespread{1.04}
% TODO: nicer math font?

% More encoding and typesetting fixes and tweaks
\RequirePackage[babel,protrusion=true,expansion=true]{microtype}
\RequirePackage{hyphenat}

% Graphics insertion and filetypes' order of precedence
\RequirePackage{graphicx}
\DeclareGraphicsRule{.out.png}{png}{.out.png}{}
\DeclareGraphicsExtensions{.out.png,.pdf,.png,.jpg}

% For hyperref<->algorithm interaction
\RequirePackage{float}

% Cross-references are clickable
\RequirePackage[bookmarks=true,
                bookmarksnumbered=true,
                colorlinks=false,
                pdfdisplaydoctitle=true,
                breaklinks=true]{hyperref}
% Link to beginning of floats
\RequirePackage[all]{hypcap}

% Captions
\RequirePackage[font=small, labelfont=bf, labelsep=endash, margin=1cm]{caption}

% Subfigures
\RequirePackage{subcaption}

% Citations
\RequirePackage[backend=bibtex,style=alphabetic]{biblatex}
\defbibheading{bibliography}[\refname]{\chapter*{#1}\chaptermark{#1}}

% The "SI" and "num" commands for typesetting units
%\RequirePackage[sepfour=true,tophrase=\dots,per=slash,obeyall]{siunitx}
%\RequirePackage[range-phrase={\dots\,},per-mode=symbol,detect-all,load-configurations=binary,forbid-literal-units]{siunitx}
\RequirePackage[range-phrase={\dots\,},per-mode=symbol,detect-all,binary-units]{siunitx}
\DeclareSIUnit\byte{Byte}
\DeclareSIUnit\decibelm{dBm}
\DeclareSIUnit\mph{mph}

% Commands for beautiful tables
\RequirePackage{booktabs}

% Equation typesetting fixes and tweaks + proof/theorem environment
\RequirePackage{amsmath}
\newtheorem{thm}{Theorem}[section]
\everydisplay={\setlength{\abovedisplayshortskip}{-0.5em plus1ex minus1ex}\setlength{\abovedisplayskip}{-0.5em plus1ex minus1ex}}

% -----------------------------------------------------------------------------


% -----------------------------------------------------------------------------
% Internationalization support
% -----------------------------------------------------------------------------

% Multi-language support using Babel
%\let\myoldshow\show\renewcommand{\show}{}  % temporarily disable \show command, as babeltools 2010/10/14 seems to use it
%\RequirePackage[shorthands=off]{babeltools}  % don't use any shorthands (i.e. "a will not try to produce an umlaut)
%\let\show\myoldshow\renewcommand{\myoldshow}{}  % re-enable \show command
\ifthenelse{\boolean{germanthesis}}{
  \RequirePackage[shorthands=off,american,ngerman]{babel}
  \def\cvtitle{Lebenslauf}
}{
  \RequirePackage[shorthands=off,ngerman,american]{babel}
  \def\cvtitle{Curriculum Vitae}
}

% Time and date functions
\RequirePackage{datetime}

% Clever References
\ifthenelse{\boolean{germanthesis}}{
	\RequirePackage[ngerman,nameinlink]{cleveref}[2009/17/04]
	\def\cref{\Cref}
	\def\crefrange{\Crefrange}
	\crefname{lstlisting}{Listing}{Listings}
	\Crefname{lstlisting}{Listing}{Listings}
	\crefname{listing}{Listing}{Listings}
	\Crefname{listing}{Listing}{Listings}
	\crefname{algorithm}{Algorithmus}{Algorithmen}
	\Crefname{algorithm}{Algorithmus}{Algorithmen}
}{
	\RequirePackage[nameinlink]{cleveref}[2009/17/04]
	\def\cref{\Cref}
	\def\crefrange{\Crefrange}
	\crefname{lstlisting}{listing}{listings}
	\Crefname{lstlisting}{Listing}{Listings}
	\crefname{listing}{listing}{listings}
	\Crefname{listing}{Listing}{Listings}
	\crefname{algorithm}{algorithm}{algorithms}
	\Crefname{algorithm}{Algorithm}{Algorithms}
}

% Some more language-dependent commands
\ifthenelse{\boolean{germanthesis}}{
  \newcommand{\thedate}{\today}
  \newcommand{\glossarytitlename}{Abkürzungsverzeichnis}
  \newcommand{\listoftitlename}{Verzeichnisse}
}{
  \RequirePackage[german,american]{isodate}
  \newcommand{\thedate}{
    \makeatletter
    \def\iso@languagename{german}%
    \dategerman%
    \today
    \def\iso@languagename{american}%
    \makeatother
  }
  \newcommand{\listoftitlename}{Lists}
  \newcommand{\glossarytitlename}{List of Acronyms}
}

% Language-independent timestamp
\newcommand{\timestamp}{\renewcommand{\dateseparator}{-}\yyyymmdddate\today\quad\settimeformat{hhmmsstime}\currenttime}

% -----------------------------------------------------------------------------


% -----------------------------------------------------------------------------
% All the simple stuff goes here
% -----------------------------------------------------------------------------

% The Acronym package
\RequirePackage{acro}

% Make automatically inserted "blank pages" really blank
\RequirePackage{emptypage}

% Fix spacing around "..."
\RequirePackage{ellipsis}

% TeX ist kein Zeichenprogramm
\RequirePackage{tikz}[2010/10/13]

% Sans Serif Font for tikzpictures
\tikzset{every picture/.append style={font=\sffamily}}

% This removes the auto anchor feature, when an explicit anchor is given
\tikzset{anchor/.append code={\let\tikz@auto@anchor\relax\let\tikz@compute@direction\pgfutil@gobble}}

% Ensure that no floats are typeset before they are referenced
\RequirePackage{flafter}

% Provide the \FloatBarrier command that flushes all pending floats
\RequirePackage{placeins}

% Nag about deprecated LaTeX packages and commands
\RequirePackage[l2tabu, orthodox]{nag}

% Define command that will return current filename
\ifthenelse{\boolean{watermark}}{
  \RequirePackage{currfile}
}{}

% Do not reset footnote counter on new chapter
\RequirePackage[]{chngcntr}
\counterwithout{footnote}{chapter}

% "Draft" watermark
\newcommand{\thewatermark}{\ifthenelse{\boolean{watermark}}{%
	\begin{tikzpicture}[remember picture, overlay]
		\node[anchor=south, outer sep=3.75cm] at (current page.south) {
			\color{gray}\currfilename\quad\timestamp
		};
	\end{tikzpicture}%
}{}}

% The "algorithm" environment
\RequirePackage{algorithmic}[2009/08/24]
\RequirePackage[plain,chapter]{algorithm}

\renewcommand\fs@plain{%
\def\@fs@cfont{\rmfamily}%
\let\@fs@capt\floatc@plain%
\def\@fs@pre{\hrule\relax\kern2pt}%
\def\@fs@post{}%
\def\@fs@mid{\kern2pt\hrule\relax\vspace\abovecaptionskip\relax}%
\let\@fs@iftopcapt\iffalse%
}
\floatstyle{plain}
\restylefloat{algorithm}
\ifthenelse{\boolean{germanthesis}}{
	\floatname{algorithm}{Algorithmus}
	\renewcommand{\listalgorithmname}{Algorithmenverzeichnis}
}{
}

% Chapter/section headings and page styles
%\RequirePackage[pagestyles,nobottomtitles*]{titlesec}
\RequirePackage[pagestyles]{titlesec}
\ifthenelse{\boolean{plainunnumbered}}{
\renewpagestyle{plain}{%
	\sethead{}{}{}
	\setfoot{}{\thewatermark}{}
}
}{
\renewpagestyle{plain}{%
	\sethead{}{}{}
  \ifthenelse{\boolean{oneside}}{
    \setfoot{}{\mypageheadfont\thepage}{\thewatermark}
  }{
    \setfoot*{}{\thewatermark}{\mypageheadfont\thepage}
  }
}
}

% Pagestyle "fancy"
\newpagestyle{fancy}{ % keep in sync with fancy-lists style
  \ifthenelse{\boolean{oneside}}{
    \sethead*{
      \bfseries
      \toptitlemarks
      \mypageheadfont\bfseries
      \ifthechapter{
        \ifthesection{\thesection~\sectiontitle}{\thechapter~\chaptertitle}
      }{
        \chaptertitle
      }
    }{
    }{
    }
    \setfoot*{}{}{\thewatermark}
  }{
    \sethead*{
    }{
    }{
      \bfseries
      \toptitlemarks
      \mypageheadfont\bfseries
      \ifthechapter{
        \ifthesection{\thesection~\sectiontitle}{\thechapter~\chaptertitle}
      }{
        \chaptertitle
      }
    }
    \setfoot*{}{\thewatermark}{\mypageheadfont\thepage}
  }
  \headrule
}
\pagestyle{fancy}

% The listings at the end of the thesis use unnumbered chapters and sections.
% Therefore, a separate page style without numbers is required.  Otherwise, the
% outdated numbers would be used for all the following unnumbered chapters.
% Moreover, the use of \sectionmark{sectionname} at the beginning of each section
% is required to obtain the correct section name for the page header.
\newpagestyle{fancy-lists}{ % keep in sync with fancy style
  \ifthenelse{\boolean{oneside}}{
    \sethead*{
      \scshape
      \toptitlemarks
      \mypageheadfont\scshape
      \ifthechapter{
        \ifthesection{\sectiontitle}{\chaptertitle}
      }{
        \chaptertitle
      }
    }{
    }{
    }
    \setfoot*{}{}{\thewatermark}
  }{
    \sethead*{
    }{
    }{
      \scshape
      \toptitlemarks
      \mypageheadfont\scshape
      \ifthechapter{
        \ifthesection{\sectiontitle}{\chaptertitle}
      }{
        \chaptertitle
      }
    }
    \setfoot*{}{\thewatermark}{\mypageheadfont\thepage}
  }
  \headrule
}


% rename (sub)paragraph to (sub)subsubsubsection
\let\myparagraph\paragraph
\renewcommand{\paragraph}{\FIXME{in order to avoid confusion with hyperref, \\paragraph has been renamed to \\subsubsubsection}}
\let\subsubsubsection\myparagraph
\let\mysubparagraph\subparagraph
\renewcommand{\subparagraph}{\FIXME{in order to avoid confusion with hyperref, \\subparagraph has been renamed to \\subsubsubsubsection}}
\let\subsubsubsubsection\mysubparagraph

% Modern Chapter Style
\RequirePackage{calc}
\RequirePackage{textcase}
\newlength{\@chapterwidth}

\DeclareRobustCommand{\spacedallcaps}[1]{\textls[160]{\MakeTextUppercase{#1}}}

\titleformat{\chapter}[display]%
{\relax}% Format
{\mbox{}\marginpar{\color{gray}\fontsize{96pt}{96pt}\selectfont%
    \setlength{\@chapterwidth}{\widthof{\thechapter}}%
    \vspace{-25pt}\hspace{-1.2\@chapterwidth}%
    \thechapter
  }}%Label
{0pt}% Seperator
{\vspace*{.9\baselineskip}\raggedright\huge\bfseries\spacedallcaps} %BeforeCode
[\normalsize\titlerule]% AfterCode

% Styles for the other Structure elements
\titleformat{\section}{\myheadingfont\Large\bfseries}{\thesection}{1em}{}
\titleformat{\subsection}{\myheadingfont\large\bfseries}{\thesubsection}{1em}{}
\titleformat{\subsubsection}{\myheadingfont\normalsize\bfseries}{\thesubsubsection}{1em}{}
\titleformat{\paragraph}{\myheadingfont\normalsize\bfseries}{\theparagraph}{1em}{}
\titleformat{\subparagraph}{\myheadingfont\normalsize}{\thesubparagraph}{1em}{\labelitemi~}
\titlespacing*{\chapter}{0pt}{50pt}{40pt}
\titlespacing*{\section}{0pt}{3.5ex plus 1ex minus .2ex}{2.3ex plus .2ex}
\titlespacing*{\subsection}{0pt}{3.25ex plus 1ex minus .2ex}{1.5ex plus .2ex}
\titlespacing*{\subsubsection}{0pt}{3.25ex plus 1ex minus .2ex}{1.5ex plus .2ex}
\titlespacing*{\paragraph}{0pt}{3.25ex plus 1ex minus .2ex}{1.5ex plus .2ex}
\titlespacing*{\subparagraph}{0pt}{3.25ex plus 1ex minus .2ex}{1.5ex plus .2ex}

\setcounter{tocdepth}{3}
\setcounter{secnumdepth}{3}


% SRA Cover Page
\RequirePackage{vsscoverpage}
% -----------------------------------------------------------------------------


% -----------------------------------------------------------------------------
% Commands for setting author, title, ...
% -----------------------------------------------------------------------------
\renewcommand{\author}[1]{\gdef\theauthor{#1}}
\renewcommand{\title}[1]{\gdef\thetitle{#1}}
\newcommand{\studentid}[1]{\gdef\thestudentid{#1}}
\newcommand{\germantitle}[1]{\gdef\thegermantitle{#1}}
\newcommand{\thesistype}[1]{\gdef\thethesistype{#1}}
\newcommand{\thesiscite}[1]{\gdef\thethesiscite{#1}}
\newcommand{\birthday}[1]{\gdef\thebirthday{#1}}
\newcommand{\birthplace}[1]{\gdef\thebirthplace{#1}}
\newcommand{\thesisstart}[1]{\gdef\thethesisstart{#1}}
\newcommand{\thesisend}[1]{\gdef\thethesisend{#1}}
\newcommand{\advisors}[1]{\gdef\theadvisors{#1}}
\newcommand{\examiner}[1]{\gdef\theexaminer{#1}}
\newcommand{\coexaminer}[1]{\gdef\thecoexaminer{#1}}
\newcommand{\dean}[1]{\gdef\thedean{#1}}
% -----------------------------------------------------------------------------


% -----------------------------------------------------------------------------
% Listings
% -----------------------------------------------------------------------------
\RequirePackage{listing} % For \listoflistings
\RequirePackage{listings}
\ifthenelse{\boolean{germanthesis}}{
    \gdef\listlistingname{Quellcodeverzeichnis}
	\renewcommand{\lstlistlistingname}{Quellcodeverzeichnis}
}{
    \gdef\listlistingname{List of Listings}
	\renewcommand{\lstlistlistingname}{List of Listings}
}

% leave a gap between entries in list of listings that belong to different
% chapters so it is consistent with list of tables and figures
\let\Chapter\chapter
\def\chapter{\addtocontents{lol}{\protect\addvspace{10pt}}\Chapter}

\definecolor{backcolor}{rgb}{0.97,0.97,0.97}
\lstset{
	language=C,
	frame=lines,
	framesep=5pt,
	captionpos=b,
	abovecaptionskip=1em,
	numbers=left,
	xleftmargin=15pt,
	framexleftmargin=15pt,
	numberstyle=\ttfamily\scriptsize,
	numbersep=5pt,
	stepnumber=1,
	fontadjust,
	tabsize=2,
	showtabs=false,
	showspaces=false,
	showstringspaces=false,
	breaklines=true,
	breakatwhitespace=true,
	backgroundcolor=\color{backcolor},
	keywordstyle=\color{NavyBlue},
	commentstyle=\color{Gray},
	stringstyle=\color{Mahogany},
	prebreak=\raisebox{0ex}[0ex][0ex]{\color{gray}\ensuremath{\searrow}},
	basicstyle=\ttfamily\color{black}\small
}
\lstdefinestyle{txt}{
	float,
	language=C
}
\lstdefinestyle{xml}{
	float,
	language=XML
}
% -----------------------------------------------------------------------------


% -----------------------------------------------------------------------------
% TOCs
% -----------------------------------------------------------------------------

% Include list-of-Xs in table of contents
\RequirePackage[nottoc,notlot,notlof]{tocbibind}
\newcommand{\mymakeglossarytocentry}{}
\newcommand{\mymaketodotocentry}{}

% -----------------------------------------------------------------------------


% -----------------------------------------------------------------------------
% Visible TODO and FIXME markers
% -----------------------------------------------------------------------------
\ifthenelse{\boolean{germanthesis}}{
	\RequirePackage[colorinlistoftodos, textwidth=2.8cm, shadow, ngerman]{todonotes}
	\makeatletter
	\@todonotes@SetTodoListName{Offene Punkte}
	\makeatother
}{
	\RequirePackage[colorinlistoftodos, textwidth=3.0cm, shadow]{todonotes}
}
\newcounter{TODOCOUNT}
\newcommand{\TODO}[1]{\vspace{0.5em}\todo[inline, color=orange]{#1}\stepcounter{TODOCOUNT}}
\newcommand{\FIXME}[1]{\todo[size=\small, color=red]{#1}\stepcounter{TODOCOUNT}}
\AtEndDocument{
	\ifnum\value{TODOCOUNT}>0
		%\cleardoublepage
		\mymaketodotocentry\listoftodos
	\fi
}
% -----------------------------------------------------------------------------


% -----------------------------------------------------------------------------
% Title page
% -----------------------------------------------------------------------------
\renewcommand{\maketitle}{%

% Do some stuff we had to postpone until after e.g. \thetitle was set
\hypersetup{%
  pdftitle = {\thetitle},
  pdfsubject = {\thethesistype},
  pdfauthor = {\theauthor},
  pdfborder=0 0 0
}

\pagenumbering{alph}

% Output cover page
\makecoverpage

% Title pages use single line spacing, no parindent and no parskips
\begin{singlespace}
\setlength\parindent{0pt}
\setlength\parskip{0pt}

%
% Der Schmutztitel (https://de.wikipedia.org/wiki/Schmutztitel)
%

\pagestyle{empty}
\pagenumbering{roman}

\thispagestyle{empty}

\vspace*{0.8cm}

\begin{center}

{\LARGE \textbf{\thetitle}}\\[2\baselineskip]

{\large
\thethesistype\\[2\baselineskip]

vorgelegt von\\[2\baselineskip]

\textbf{\theauthor}\\[1\baselineskip]
Matr.Nr.: \thestudentid\\[1\baselineskip]


\ifthenelse{\boolean{privacy}}{}{%
geb. am \thebirthday\\
in \thebirthplace\\[2\baselineskip]
}

angefertigt am\\[2\baselineskip]

\textbf{Institut für Systems Engineering\\[0.2\baselineskip]
Fachgebiet Verl\"assliche und Skalierbare Softwaresysteme\\[1.2\baselineskip]
Fakultät für Elektrotechnik und Informatik\\[0.2\baselineskip]
Leibniz Universität Hannover\\[0.2\baselineskip]
}
}~\\[1\baselineskip]

\begin{tabular}{>{\raggedleft}p{6cm}p{9cm}}
Erstprüfer: & \textbf{\theexaminer}\\
Zweitprüfer: & \textbf{\thecoexaminer}\\
Betreuer:   \theadvisors
  ~ & ~\\
  ~ & ~\\
Beginn der Arbeit: & \textbf{\thethesisstart}\\
Abgabe der Arbeit: & \textbf{\thethesisend}\\
\end{tabular}

\end{center}

\clearpage

\end{singlespace}

\thispagestyle{empty}
\mbox{}\clearpage
%
% The delaration comes here
%

\thispagestyle{empty}

\begin{otherlanguage*}{ngerman}
{\Large\noindent%
Erklärung \newline}

\noindent%
Ich versichere, dass ich die Arbeit ohne fremde Hilfe und ohne Benutzung anderer als der angegebenen Quellen angefertigt habe und dass die Arbeit in gleicher oder ähnlicher Form noch keiner anderen Prüfungsbehörde vorgelegen hat und von dieser als Teil einer Prüfungsleistung angenommen wurde.
Alle Ausführungen, die wörtlich oder sinngemäß übernommen wurden, sind als solche gekennzeichnet.
\end{otherlanguage*}


\vspace{2cm}


\begin{otherlanguage*}{american}
{\Large\noindent%
Declaration \newline}

\noindent%
I declare that the work is entirely my own and was produced with no assistance from third parties.
I certify that the work has not been submitted in the same or any similar form for assessment to any other examining body and all references, direct and indirect, are indicated as such and have been cited accordingly.
\end{otherlanguage*}


\vspace{3cm}


\noindent%
(\theauthor)\\
Hannover, \thedate

\cleardoublepage
}

%
% workaround for a bug in texlive 2016's titlesec package that prevents section
% numbers from being shown, cf.
% https://tex.stackexchange.com/questions/299969/titlesec-loss-of-section-numbering-with-the-new-update-2016-03-15
%
\RequirePackage{etoolbox}
\makeatletter
\patchcmd{\ttlh@hang}{\parindent\z@}{\parindent\z@\leavevmode}{}{}
\patchcmd{\ttlh@hang}{\noindent}{}{}{}
\makeatother

% -----------------------------------------------------------------------------
