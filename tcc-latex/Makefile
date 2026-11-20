MAIN = tcc-gustavo

.PHONY: all clean distclean

all: $(MAIN).pdf

$(MAIN).pdf: $(MAIN).tex $(MAIN).bib
	latexmk -pdf -interaction=nonstopmode -synctex=1 $(MAIN).tex

clean:
	latexmk -c $(MAIN).tex

distclean:
	latexmk -C $(MAIN).tex
