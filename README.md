# GemmaRAG iOS — iPad Pro M4 PoC

Natywna aplikacja iOS implementujaca pipeline RAG z repozytorium Python.
Gemma 4 E2B (GGUF Q4_K_M) + vector search + evidence images, w pelni offline.

## Architektura

```
Python PoC                    ->  iOS Swift
─────────────────────────────────────────────
llama-cpp-python (GGUF)       ->  llama.cpp Swift Package (Metal GPU)
sentence-transformers MiniLM  ->  keyword search + pseudo-embeddings*
FAISS / SQLite-VSS            ->  Accelerate vDSP brute-force cosine
Flask HTML pseudo-UI          ->  SwiftUI chat interface
```

*Pre-computed corpus embeddings are bundled. Query embedding uses
weighted average of keyword-matched chunk embeddings as approximation.

## Przygotowanie danych

Na laptopie Windows (w glownym repo):

```bash
pip install numpy pyyaml
python scripts/export_ios_bundle.py
```

To generuje `ios/GemmaRAG/Resources/` z:
- `chunks.json` (dane chunkow)
- `embeddings.bin` (pre-computed embeddings float32)
- `images/` (evidence images PNG)
- `config.json` (parametry RAG)

## Build

Repo musi byc na GitHub (publiczne dla darmowych minut CI).

1. Skopiuj `.github/` z `ios/.github/` do roota repo
2. Push do GitHub
3. Actions -> "Build iOS" -> "Run workflow"
4. Pobierz artefakt `GemmaRAG-ipa`

## Instalacja na iPadzie

1. Pobierz [Sideloadly](https://sideloadly.io) na Windows
2. Polacz iPada kablem USB
3. Otworz Sideloadly, wybierz plik `.ipa`
4. Wpisz Apple ID (darmowe, osobiste)
5. Kliknij "Start" — apka pojawi sie na iPadzie

**Uwaga:** Darmowy certyfikat wygasa co 7 dni. Trzeba powtorzyc sideload.

## Uzycie na iPadzie

1. Otworz GemmaRAG
2. Kliknij "Select GGUF File" -> wybierz model z Files
3. Poczekaj na zaladowanie (~30s dla E2B Q4_K_M)
4. Zadaj pytanie w czacie
5. Wlacz "Include evidence images" dla pytan z obrazkami

## Metryki

Aplikacja wyswietla przy kazdej odpowiedzi:
- **tok/s** — predkosc generacji (tokens per second)
- **TTFT** — Time to First Token (ms)
- **tokens** — liczba wygenerowanych tokenow
- **conf** — retrieval confidence (%)
