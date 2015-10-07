# Find expression that created a variable
find_expr <- function(name, env = parent.frame()) {
  subs <- do.call("substitute", list(as.name(name), env))
  paste0(deparse(subs, width.cutoff = 500), collapse = "\n")
}

# A version of grepl that's vectorised along pattern, not x
grepl2 <- function(pattern, x, ...) {
  stopifnot(length(x) == 1)
  
  vapply(pattern, grepl, x, ..., FUN.VALUE = logical(1), USE.NAMES = FALSE)
}

# Nicely collapse a character vector
collapse <- function(x, conn = " and ") {
  if (length(x) > 1) {
    n <- length(x)
    last <- c(n-1, n)
    collapsed <- paste(x[last], collapse = conn)
    collapsed <- paste(c(x[-last], collapsed), collapse = ", ")
  } else collapsed <- x
  collapsed
}

collapse_args <- function(x, conn = " and ") {
  collapse(paste0("<code>",x,"</code>"), conn)
}

collapse_props <- function(x, conn = " and ") {
  collapse(paste0("<code>",x,"</code>"), conn)
}

collapse_funs <- function(x, conn = " and ") {
  collapse(paste0("<code>",x,"()</code>"), conn)
}

get_num <- function(index) {
  switch(index, 
         "1" = "first", "2" = "second", 
         "3" = "third", "4" = "fourth", 
         "5" = "fifth", "6" = "sixth", 
         "7" = "seventh", sprintf("%ith", index))
}

#' convert student/solution code to vector of clean strings with the pipe operator removed.
#' 
#' @param code the code to convert to a vector of unpiped clean strings 
#' @export
get_clean_lines <- function(code) {
  # convert summarize to summarise. (hacky solution)
  code = gsub("summarize","summarise",code)
  
  pd <- getParseData(parse(text = code, keep.source = TRUE))
  exprids <- pd$id[pd$parent == 0 & pd$token != "COMMENT"]
  codelines <- sapply(exprids, function(x) getParseText(pd, id = x))
  
  cleanlines <- sapply(codelines, clean_unpipe, USE.NAMES = FALSE)
  
  # remove "obj = " assignments: delete "=" lines and the ones preceding
  eqsubsids = which(cleanlines == "=", TRUE)
  if(length(eqsubsids) == 0) {
    return(cleanlines)
  } else {
    removeids = c(eqsubsids, eqsubsids-1)
    return(cleanlines[-removeids])
  }
}

# subfunction used by get_clean_lines to remove the pipe operator.
clean_unpipe <- function(code) {
  if(grepl("%>%",code)) {
    return(paste0(deparse(unpipe(as.call(parse(text=code))[[1]])),collapse = ''))
  } else {
    return(code)
  }
}

# Convert an expression that uses the pipe operator to a regular embedded expression.
unpipe <- function(expr) {
  cnv <- function(x) {
    lhs <- x[[2]]
    rhs <- x[[3]]
    
    dot_pos <- which(
      vapply(rhs
             , function(x) paste0(as.character(x), collapse = "") == "."
             , logical(1)
             , USE.NAMES = FALSE))
    
    if (any(all.names(rhs) == "%>%")) rhs <- decomp(rhs)
    if (any(all.names(lhs) == "%>%")) lhs <- decomp(lhs)
    
    # main
    if (length(dot_pos) > 0) {
      rhs[[dot_pos]] <- lhs
      rhs
    } else if (is.symbol(rhs) || rhs[[1]] == "function" || rhs[[1]] == "(") {
      as.call(c(rhs, lhs))
    } else if (is.call(rhs)) {
      as.call(c(rhs[[1]], lhs, lapply(rhs[-1], decomp)))
    } else {
      stop("missing condition error")
    }
  }
  
  decomp <- function(x) {
    if (length(x) == 1) x
    else if (length(x) == 3 && x[[1]] == "%>%") cnv(x)
    else if (is.pairlist(x)) as.pairlist(lapply(x, decomp))
    else as.call(lapply(x, decomp))
  }
  decomp(expr)
}


# build R markdown document structure, using knitr functions
build_doc_structure <- function(text) {
  require(knitr)
  
  # Fix markdown format
  old.format <- knitr:::opts_knit$get()
  knitr:::opts_knit$set(out.format = "markdown")
  
  # Fix pattern business
  apat = knitr::all_patterns; opat = knit_patterns$get()
  on.exit({
    knit_patterns$restore(opat)
    knitr:::chunk_counter(reset = TRUE)
    knitr:::knit_code$restore(list())
    knitr:::opts_knit$set(old.format)
  })
  pat_md()
  
  # split the file
  content = knitr:::split_file(lines = knitr:::split_lines(text)) 
  code_chunks <- knitr:::knit_code$get()
  
  for(i in seq_along(content)) {
    if(class(content[[i]]) == "block") {
      label <- content[[i]]$params$label
      content[[i]]$input <- paste(code_chunks[[label]],collapse = "\n")
    }
  }  
  
  # remove the inline blocks that contain nothing or only spaces:
  content[sapply(content, function(part) {
    all(grepl(pattern = "^\\s*$", x = part$input.src)) && class(part) == "inline"
  })] <- NULL
  
  return(content)
}

# Parse both the student and solution document
parse_docs <- function(student_code = get_student_code(), solution_code = get_solution_code()) {
  if(exists_student_ds() & exists_solution_ds()) {
    # Both variables exist already
    return(TRUE)
  }
  if(is.null(student_code) || is.null(solution_code)) {
    stop("The 'student_code' and/or 'solution_code' argument(s) can not be empty")
  }
  
  student_ds = build_doc_structure(student_code) #list(list(input = ""))
  solution_ds = build_doc_structure(solution_code) #list(list(input = ""))
  
  n_student = length(student_ds)
  n_solution = length(solution_ds)
  n_inline_student = sum(sapply(student_ds, class) == "inline")
  n_inline_solution = sum(sapply(solution_ds, class) == "inline")
  n_block_student = sum(sapply(student_ds, class) == "block")
  n_block_solution = sum(sapply(solution_ds, class) == "block")
  
  test_what(expect_equal(n_student, n_solution),
            sprintf("Make sure the structure of your document is OK. The solution expects %i inline (text) blocks and %i code chunks.", n_inline_solution, n_block_solution))
  
  test_what(expect_equal(n_inline_student, n_inline_solution), 
            sprintf("Make sure you have the correct amount of inline (text) blocks in your R markdown document. The solution expects %i.",n_inline_solution))
  
  test_what(expect_equal(n_block_student, n_block_solution),
            sprintf("Make sure you have the correct amount of code blocks in your R markdown document. The solution expects %i.", n_block_solution))
  
  test_what(expect_true(all.equal(sapply(student_ds, class), sapply(solution_ds, class))),
            sprintf("Make sure the overall code structure of your document is OK. The soltion expects the following setup: %s.", 
                    collapse_props(sapply(solution_ds, class), conn = ", ")))
  
  if(n_student != n_solution) return(FALSE)
  if(n_inline_student != n_inline_solution) return(FALSE) 
  if(n_block_student != n_block_solution) return(FALSE)
  if(!isTRUE(all.equal(sapply(student_ds, class), sapply(solution_ds, class)))) return(FALSE)
  
  set_student_ds(student_ds)
  set_solution_ds(solution_ds)
  return(TRUE)
}