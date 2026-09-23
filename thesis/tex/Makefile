.PHONY: all data clean
all:
	latexmk -pdf -interaction=nonstopmode -halt-on-error thesis.tex
data:
	python3 prepare_data.py
	python3 prepare_provenance.py
clean:
	latexmk -c thesis.tex
