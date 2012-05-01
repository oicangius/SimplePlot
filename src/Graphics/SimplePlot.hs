{-# LANGUAGE FlexibleInstances, TypeSynonymInstances, IncoherentInstances #-}

{- A simple plotting library, utilizes gnuplot for plotting.

   2012 by Julian Fleischer <julian dot fleischer at fu dash berlin dot de>
-}

-- | A simple wrapper to the gnuplot command line utility.
--   Make sure "gnuplot" is in your path and everything should work.
--
-- Typically you will invoke a plot like so:
--
-- > plot X11 $ Data2D [Title "Sample Data"] [] [(1, 2), (2, 4), ...]
--
-- To plot a function, use the following:
--
-- > plot X11 $ Function2D [Title "Sine and Cosine"] [] (\x -> sin x * cos x)
--
-- There is also a shortcut available - the following plots the sine function:
--
-- > plot X11 sin
--
-- Output can go into a file, too:
--
-- > plot (PNG "plot.png") (sin . cos)
--
-- Haskell functions are plotted via a set of tuples obtained form the function.
-- If you want to make use of gnuplots mighty function plotting functions you can
-- pass a 'Gnuplot2D' or 'Gnuplot3D' object to plot.
--
-- > plot X11 $ Gnuplot2D [Color Blue] [] "2**cos(x)"
--
-- For 3D-Plots there is a shortcut available by directly passing a String:
--
-- > plot X11 "x*y"
module Graphics.SimplePlot (

    -- * Plotting
    Plot (plot),

    -- * Graphs for 2D and 3D plots
    Graph2D (..), Graph3D (..),

    -- * Configuration and other options
    TerminalType (..),
    Color (..), Style (..), -- Style2D (..),
    Option (..), Option2D (..), Option3D (..)

    ) where

import Numeric (showHex)
import Data.Char (toUpper)
import Data.List (sortBy, nubBy)
import System.Cmd (rawSystem)
import System.Exit (ExitCode (ExitSuccess))

-- | TerminalType determines where the output of gnuplot should go.
data TerminalType = Aqua    -- ^ Output on Mac OS X (Aqua Terminal).
                  | Windows -- ^ Output for MS Windows.
                  | X11     -- ^ Output to the X Window System.
                  | PS FilePath -- ^ Output into a Postscript file.
                  | EPS FilePath -- ^ Output into an EPS file.
                  | PNG FilePath -- ^ Output as Portable Network Graphic into file.
                  | PDF FilePath -- ^ Output as Portable Document Format into a file.
                  | SVG FilePath -- ^ Output as Scalable Vector Graphic into a file.
                  | GIF FilePath -- ^ Output as Graphics Interchange Format into a file.
                  | JPEG FilePath -- ^ Output into a JPEG file.
                  | Latex FilePath -- ^ Output as LaTeX.

-- | The Style of a graph.
data Style = Lines  -- ^ points in the plot are interconnected by lines.
           | Points -- ^ data points are little cross symbols.
           | Dots   -- ^ data points are real dots (approx the size of a pixel).
    deriving Show

{- Impulses Linespoints -}

-- | The Color of a graph.
data Color = Red | Blue | Green | Yellow | Orange | Magenta | Cyan
           | DarkRed | DarkBlue | DarkGreen | DarkYellow | DarkOrange | DarkMagenta | DarkCyan
           | LightRed | LightBlue | LightGreen | LightMagenta
           | Violet | White | Brown | Grey | DarkGrey | Black
           | RGB Int Int Int -- ^ a custom color
    deriving Show

data Style2D = Boxerrorbars | Boxes | Boxyerrorbars
             | Filledcurves | Financebars | Fsteps | Histeps | Histograms
             | Steps | Xerrorbars | Xyerrorbars | Yerrorbars | Xerrorlines
             | Xyerrorlines | Yerrorlines

-- | Options on how to render a graph.
data Option = Style Style   -- ^ The style for a graph.
            | Title String  -- ^ The title for a graph in a plot (or a filename like @plot1.dat@).
            | Color Color   -- ^ The line-color for the graph (or if it consist of 'Dots' or 'Points' the color of these)
    deriving Show

-- | Options which are exclusively available for 2D plots.
data Option2D x y = Range x x | For [x] | Step x

-- | Options which are exclusively available for 3D plots.
data Option3D x y z = RangeX x x | RangeY y y | ForX [x] | ForY [y] | StepX x | StepY y

-- | A two dimensional set of data to plot.
data Graph2D x y =
      Function2D   [Option] [Option2D x y] (x -> y)
    | Data2D       [Option] [Option2D x y] [(x, y)]
    | Gnuplot2D    [Option] [Option2D x y] String
      -- ^ plots a custom function passed to Gnuplot (like @x**2 + 10@) 

-- | A three dimensional set of data to plot.
data Graph3D x y z =
      Function3D   [Option] [Option3D x y z] (x -> y -> z)
      -- ^ plots a Haskell function

    | Data3D       [Option] [Option3D x y z] [(x, y, z)]
      -- ^ plots a dataset

    | Gnuplot3D    [Option] [Option3D x y z] String
      -- ^ plots a custom function passed to Gnuplot (like @x*y@)

-- | Provides the plot function for different kinds of graphs (2D and 3D)
class Plot a where

    -- | Do a plot to the terminal (i.e. a window will open and your plot can be seen)
    plot :: TerminalType -- ^ The terminal to be used for output.
            -> a         -- ^ The graph to plot. A 'Graph2D' or 'Graph3D' or a list of these.
            -> IO Bool   -- ^ Whether the plot was successfull or not.


-- | 'plot' can be used to plot a single 'Graph2D'.
instance (Fractional x, Enum x, Show x, Num y, Show y) => Plot (Graph2D x y) where
    plot term graph = plot term [graph]

-- | 'plot' can be used to plot a list of 'Graph2D'.
instance (Fractional x, Enum x, Show x, Num y, Show y) => Plot [Graph2D x y] where
    plot term graphs = exec [toString term] "plot" options datasources
        where   (options, datasources) = unzip $ map prepare graphs
                prepare (Gnuplot2D  opt opt3d g) = (opts $ sanitize opt, Right $ g)
                prepare (Data2D     opt opt3d d) = (opts $ sanitize opt, Left  $ toString d)
                prepare (Function2D opt opt3d f) = (opt', Left $ plotData)
                    where   (opt', plotData) = render2D opt f

-- | 'plot' can be used to plot a single 'Graph3D'.
instance (Fractional x, Enum x, Show x, Fractional y, Enum y, Show y, Num z, Show z) => Plot (Graph3D x y z) where
    plot term graph = plot term [graph]

-- | 'plot' can be used to plot a list of 'Graph3D'
instance (Fractional x, Enum x, Show x, Fractional y, Enum y, Show y, Num z, Show z) => Plot [Graph3D x y z] where
    plot term graphs = exec [toString term] "splot" options datasources
        where   (options, datasources) = unzip $ map prepare graphs
                prepare (Gnuplot3D  opt opt3d g) = (opts $ sanitize opt, Right $ g)
                prepare (Data3D     opt opt3d d) = (opts $ sanitize opt, Left  $ toString d)
                prepare (Function3D opt opt3d f) = (opt', Left $ plotData)
                    where   (opt', plotData) = render3D opt f

-- | A 2D function can be plotted directly using 'plot'
instance (Fractional x, Enum x, Show x, Num y, Show y) => Plot (x -> y) where
    plot term f = plot term $ Function2D [] [] f

-- | A list of 2D functions can be plotted directly using 'plot'
instance (Fractional x, Enum x, Show x, Num y, Show y) => Plot [x -> y] where
    plot term fs = plot term $ map (Function2D [] []) fs

-- | A 3D function can be plotted directly using 'plot'
instance (Fractional x, Enum x, Show x, Fractional y, Enum y, Show y, Num z, Show z) => Plot (x -> y -> z) where
    plot term f = plot term $ Function3D [] [] f

-- | A list of 3D functions can be plotted directly using 'plot'
instance (Fractional x, Enum x, Show x, Fractional y, Enum y, Show y, Num z, Show z) => Plot [x -> y -> z] where
    plot term fs = plot term $ map (Function3D [] []) fs

-- | A list of tuples can be plotted directly using 'plot'
instance (Fractional x, Enum x, Num x, Show x, Num y, Show y) => Plot [(x, y)] where
    plot term d = plot term $ Data2D [] [] d

-- | A list of triples can be plotted directly using 'plot'
instance (Fractional x, Enum x, Show x, Fractional y, Enum y, Show y, Num z, Show z) => Plot [(x, y, z)] where
    plot term d = plot term $ Data3D [] [] d

-- | plot accepts a custom string which is then to be interpreted by gnu plot. The function will be interpreted as 'Gnuplot3D'.
instance Plot String where
    plot term g = plot term $ Gnuplot3D [] [] g

instance Plot [String] where
    plot term g = plot term $ map (Gnuplot3D [] []) g

-- | INTERNAL: Prepares 2D plots of haskell functions.
render2D opt f = (opts $ sanitize (opt ++ [Style Lines]), plot2D f)
plot2D f = toString [(x, f x) | x <- [-5,-4.95..5]]

-- | INTERNAL: Prepares 3D plots of haskell functions.
render3D opt f = (opts $ sanitize (opt), plot3D f)
plot3D f = toString [(x, y, f x y) | x <- [-5,-4.95..5], y <- [-5,-4.95..5]]

-- | INTERNAL: Sanitizes options given via Graph-Objects
sanitize = sortBy ord . nubBy dup
    where   ord a b
                | dup a b = EQ
                | True    = ord' a b
            ord' (Style _) (Title _) = LT
            ord' (Style _) (Color _) = LT
            ord' (Color _) (Title _) = GT
            ord' a b
                | ord' b a == LT = GT
                | True           = LT
            dup (Title _) (Title _) = True
            dup (Style _) (Style _) = True
            dup (Color _) (Color _) = True
            dup _ _                 = False

-- | INTERNAL: Translates options into gnuplot commands
opts [] = ""
opts [x] = toString x
opts (x:xs) = toString x ++ " " ++ opts xs

-- | INTERNAL: Invokes gnuplot.
--
-- Can be invoked like so:
--
-- > exec ["set terminal x11 persist"] "splot" ["with lines", "with points"] [Left "1 0 2\n2 1 1", Left "2 0 3\n1 1 2"]
--
-- or so:
--
-- > exec ["set terminal x11 persist"] "splot" ["width lines", "with lines"] [Right "x*y", Right "sin(x) + cos(y)"]
exec :: [String] -> String -> [String] -> [Either String String] -> IO Bool
exec preamble plotfunc plotops datasets =
    do
        let filenames = zipWith (\x y -> x ++ show y ++ ".dat")
                                (cycle ["plot"]) [1..length datasets]

        mapM (uncurry writeFile) (zip filenames (map (either id id) datasets))

        let datasources = zipWith (\x y -> either (const (Left x)) Right y) filenames datasets

            file y x = "\"" ++ x ++ "\" " ++ y
            func y x =         x ++ " "   ++ y

            plotcmds = zipWith (\x y -> either (file y) (func y) x) datasources plotops
            plotstmt = foldl1  (\x y -> x ++ ", " ++ y) plotcmds
            plotcmd  = foldl1  (\x y -> x ++ "; " ++ y)
                               (preamble ++ [plotfunc ++ " " ++ plotstmt])
        
        exitCode <- rawSystem "gnuplot" ["-e", plotcmd]

        return $ exitCode == ExitSuccess

-- | INTERNAL: Provides 'toString' for translating haskell types into gnuplot commands
--   (ordinary strings)
class GnuplotIdiom a where
    toString :: a -> String

instance (Num x, Show x, Num y, Show y) => GnuplotIdiom (x, y) where
    toString (x, y) = space $ shows x $ space $ show y

instance (Num x, Show x, Num y, Show y, Num z, Show z) => GnuplotIdiom (x, y, z) where
    toString (x, y, z) = space $ shows x $ space $ shows y $ space $ show z

space x = ' ' : x

instance GnuplotIdiom Style where
    toString x = case x of
        Lines   -> "with lines"
        Points  -> "with points"
        Dots    -> "with dots"

instance GnuplotIdiom Option where
    toString x = case x of
        Title t -> "title \"" ++ t ++ "\""
        Style s -> toString s
        Color c -> "lc rgb \"" ++ toString c ++ "\""

instance GnuplotIdiom x => GnuplotIdiom [x] where
    toString = unlines . map toString

instance GnuplotIdiom (TerminalType) where
    toString t = case t of
        PNG f   -> "set term png; set output \"" ++ f ++ "\""
        PDF f   -> "set term pdf enhanced; set output \"" ++ f ++ "\""
        SVG f   -> "set term svg dynamic; set output \"" ++ f ++ "\""
        GIF f   -> "set term gif; set output \"" ++ f ++ "\""
        JPEG f  -> "set term jpeg; set output \"" ++ f ++ "\""
        Latex f -> "set term latex; set output \"" ++ f ++ "\""
        EPS f   -> "set term postscript eps; set output \"" ++ f ++ "\""
        PS f    -> "set term postscript; set output \"" ++ f ++ "\""
        Aqua    -> "set term aqua"
        Windows -> "set term windows"
        X11     -> "set term x11 persist"

instance GnuplotIdiom (Color) where
    toString (RGB r g b) = '#' : map toUpper (showHex r $ showHex g $ showHex b "")
    toString color = case color of
        Red -> "red"
        Blue -> "blue"
        Green -> "green"
        Yellow -> "yellow"
        Orange -> "orange"
        Magenta -> "magenta"
        Cyan -> "cyan"
        DarkRed -> "dark-red"
        DarkBlue -> "dark-blue"
        DarkGreen -> "dark-green"
        DarkYellow -> "dark-yellow"
        DarkOrange -> "dark-orange"
        DarkMagenta -> "aark-magenta"
        DarkCyan -> "dark-cyan"
        LightRed -> "light-red"
        LightBlue -> "light-blue"
        LightGreen -> "light-green"
        LightMagenta -> "light-magenta"
        Violet -> "violet"
        Grey -> "grey"
        White -> "white"
        Brown -> "brown"
        DarkGrey -> "dark-grey"
        Black -> "black"
