/* Letterhead chrome behaviour.
   Only what the header/footer needs: the toolbar Print button and the page
   captions. The Form 1 reflow paginator stays with the form; it is
   page-specific and needs to know which content blocks may be split.

   Load with `defer`, and with a CSP nonce if the host app sets one. */
(function () {
  "use strict";

  document.querySelectorAll("[data-print]").forEach(function (button) {
    button.addEventListener("click", function () { window.print(); });
  });

  /* Renumber the captions on a multi-sheet document: any .page-number
     carrying data-page-caption gets "Page N of M" filled in. Sheets without
     the attribute keep whatever caption the template wrote. */
  var sheets = document.querySelectorAll("main .paper");
  sheets.forEach(function (sheet, index) {
    var caption = sheet.querySelector(".page-number[data-page-caption]");
    if (caption) {
      caption.textContent = "Page " + (index + 1) + " of " + sheets.length;
    }
  });
})();
