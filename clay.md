# Clay Layout Engine - Core Algorithms

This document provides a plain English explanation of the key layout algorithms in Clay, a UI layout engine.

## Clay__SizeContainersAlongAxis

This function sizes containers along a specified axis (X or Y) by adjusting the dimensions of child elements to fit within their parent containers.

### How it works:

1. **Initialization**:
   - Get the current layout context
   - Prepare buffers for breadth-first traversal and for tracking resizable containers

2. **For each root layout element**:
   - Size floating containers to their parents if needed
   - Clamp the root element's dimensions to respect minimum/maximum constraints
   - Perform breadth-first traversal through the layout tree

3. **For each parent element encountered during traversal**:
   - Track the available size, padding, and gap information
   - Collect information about children (sizes, which ones are resizable)

4. **First pass through children**:
   - Identify which children can be resized
   - Calculate the total content size needed
   - Track how many "grow" containers exist

5. **Second pass - handle percentage-based sizing**:
   - For children with percentage-based sizing, allocate space proportional to the parent
   - Update total content size accordingly
   - Handle aspect ratio adjustments if needed

6. **When laying out along the primary axis**:
   - Calculate how much space needs to be distributed (or reclaimed)
   
   - **If content is too large for container (compression needed)**:
     - Skip compression if the parent has scrolling enabled in this direction
     - Otherwise, iteratively compress children to fit:
       1. Find the largest children
       2. Reduce their size proportionally
       3. Respect minimum size constraints
       4. Continue until everything fits or can't be compressed further
   
   - **If container has extra space and has "grow" children**:
     - Filter to keep only children that can grow
     - Iteratively expand children:
       1. Find the smallest children
       2. Increase their size proportionally
       3. Respect maximum size constraints
       4. Continue until space is filled or nothing can grow further

7. **When laying out perpendicular to the primary axis**:
   - Resize children that need to grow to fill the available space
   - Handle special cases like image aspect ratios
   - For scroll containers, allow content to be larger than the visible area

### Key Concepts:

- **Breadth-First Traversal**: Layout is processed level by level, ensuring parents are sized before their children
- **Compression Algorithm**: When content is too large, the algorithm reduces the size of the largest elements first
- **Growth Algorithm**: When space is available, the algorithm increases the size of the smallest elements first
- **Proportional Distribution**: Space is distributed based on relative sizes of elements


## Clay__CalculateFinalLayout

This function calculates the final layout of all elements, handling text wrapping, image scaling, and positioning.

### How it works:

1. **Horizontal Layout Pass**:
   - Call `Clay__SizeContainersAlongAxis(true)` to size all containers along the X axis

2. **Text Wrapping**:
   - For each text element:
     - If text fits without wrapping, create a single line
     - Otherwise, process text word by word:
       - If a word is too wide for a line, place it on its own line
       - If a word would overflow or is a newline, start a new line
       - Otherwise, add the word to the current line
     - Adjust the container's height based on the number of text lines

3. **Image Scaling**:
   - Scale image heights to maintain aspect ratio based on the calculated width

4. **Height Propagation**:
   - Use depth-first traversal to propagate height changes up the layout tree:
     - For horizontal layouts (LEFT_TO_RIGHT):
       - Adjust parent height based on the tallest child
     - For vertical layouts (TOP_TO_BOTTOM):
       - Sum all child heights plus gaps

5. **Vertical Layout Pass**:
   - Call `Clay__SizeContainersAlongAxis(false)` to size all containers along the Y axis

6. **Ordering**:
   - Sort layout elements by z-index to determine drawing order

7. **Final Positioning**:
   - Clear any existing render commands
   - For each root element:
     - Calculate its position (handling special cases like floating elements)
     - Set up clipping regions if needed
     - Using depth-first traversal:
       - Calculate each element's final position
       - Generate render commands (rectangles, text, images, etc.)
       - Position children based on layout direction and alignment
       - Handle border rendering and other visual elements

### Key Concepts:

- **Two-Pass Layout**: Horizontal pass followed by vertical pass
- **Text Wrapping**: Words are measured and wrapped to fit container width
- **Aspect Ratio Preservation**: Images maintain their aspect ratio
- **Height Propagation**: Child heights affect parent heights
- **Z-Index Ordering**: Elements are sorted for proper layering
- **Render Command Generation**: Visual representation information is prepared for rendering


## Clay__CompressChildrenAlongAxis

This functionality (embedded within `Clay__SizeContainersAlongAxis`) compresses children when there's not enough space in the parent container.

### How it works:

1. **When layout space is insufficient**:
   - Determine if compression should be skipped (e.g., for scrollable containers)
   
2. **While space is still needed and resizable containers exist**:
   - Identify the largest elements
   - Calculate how much to reduce their size:
     - Either bring them down to the size of the second-largest elements
     - Or distribute the space deficit evenly
   
3. **For each large element**:
   - Reduce its size by the calculated amount
   - If it reaches minimum size, remove it from further consideration
   - Track how much space has been reclaimed

4. **Continue iteratively** until either:
   - Enough space has been reclaimed
   - No more elements can be compressed

### Key Concepts:

- **Fairness**: Larger elements are compressed more than smaller ones
- **Minimum Constraints**: Elements won't be compressed below their minimum size
- **Progressive Compression**: Elements are compressed in stages, bringing the largest ones down first