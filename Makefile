install:
	ARU_HEADLESS_INSTALL=1 nvim --headless "!Lazy! sync" +qa

clean:
	rm -rf $(XDG_DATA_HOME)/nvim/lazy
