# akashic-pdf-image — a PDF's pictures, as files a viewer shows

A picture drawn on a PDF's page is an image XObject (PDF 32000-1, section
8.9.5): samples with their own size, space and bits, compressed by filters,
or a JPEG file inside the PDF. This module turns one into a file the
picture views already show (`media/picture.f`): a JPEG file, which a rich
terminal decodes, or a QOI file the guest writes from the samples, which
both the guest and a rich terminal decode.

```forth
REQUIRE pdf/image.f
```

`PROVIDED akashic-pdf-image`. It depends on `pdf/lexer.f`, `pdf/filter.f`,
`pdf/file.f`, `utils/inflate.f`, `render/png.f` (its `PNG-UNFILTER`),
`render/qoi.f` (its encoder by rows), `media/picture.f` (the formats and
states) and `media/source.f`.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `PDF-IMAGE-SIZE` | `( -- bytes )` | A picture's record, eight-byte aligned. |
| `PDF-IMAGE-OPEN` | `( num file image -- status )` | Read picture XObject `num`'s facts. |
| `PDF-IMAGE-FREE` | `( image -- )` | Give back everything the record holds; call it whatever the status was. |
| `PDF-IMAGE-WIDTH` | `( image -- w )` | Its width in samples. |
| `PDF-IMAGE-HEIGHT` | `( image -- h )` | Its height. |
| `PDF-IMAGE-CODING` | `( image -- coding )` | Its data's own coding: `PDF-IMG-SAMPLES`, `-DCT`, `-JPX`, `-JBIG2` or `-CCITT` (`pdf/filter.f`). |
| `PDF-IMAGE-FORMAT` | `( image -- format )` | The file it becomes, `PIC-F-JPEG` or `PIC-F-QOI`, or 0 for none. |
| `PDF-IMAGE-STEP` | `( budget image -- state )` | Make about `budget` more of that file. |
| `PDF-IMAGE-STATE@` | `( image -- state )` | `PIC-ST-PENDING`, `PIC-ST-READY` or `PIC-ST-FAILED`. |
| `PDF-IMAGE-REASON@` | `( image -- status )` | Why it failed, a `PDF-S-` status: `PDF-S-UNSUPPORTED` for a picture that makes no file. |
| `PDF-IMAGE-SOURCE` | `( image source -- )` | Make `source`, `MEDSRC-SPAN-SIZE` bytes, the ready file's media source. |

`PDF-IMAGE-OPEN` gives `PDF-S-OK` when it read the facts, whether or not
the picture makes a file; `PDF-S-DAMAGED` for an object that is no picture
or has no size; `PDF-S-MEMORY` when memory is refused.

## The files

- **A JPEG** (`DCTDecode`) stays a JPEG file. The guest does not decode it,
  so a CELL view shows its facts; a rich terminal that decodes JPEG shows
  it.
- **Samples** become a QOI file of the picture's size, three channels, or
  four with a soft mask. They are 1, 2, 4, 8 or 16 bits, a 16-bit sample by
  its high byte: gray, RGB, CMYK made RGB plainly (each of red, green and
  blue is 255 less its ink and black), or indexed over one of those, its
  palette from a string or a stream and an index past the top taking the
  top entry. `CalGray`, `CalRGB` and `ICCBased` spaces are read by their
  components. `/Decode` maps each component's range. A soft mask
  (`/SMask`), a gray picture of samples, gives alpha, each picture pixel
  taking the nearest mask pixel when their sizes differ.
- **No file** for JPEG 2000, JBIG2 and CCITT data, stencil masks
  (`/ImageMask`), Lab, Separation and DeviceN spaces, and 16-bit indexed
  samples. `PDF-IMAGE-FORMAT` is 0 and the state is failed with
  `PDF-S-UNSUPPORTED`; the width, height and coding are what a view shows.

## Making a file a step at a time

The file is made as `media/picture.f` decodes, in steps, so the caller
stays responsive. `PDF-IMAGE-STEP` makes about `budget` pixels, at least a
row, or for a JPEG copies about `budget` bytes, at least a piece of 4 KB,
and gives `PIC-ST-PENDING` until the file is ready or failed.

- A JPEG under no other filter and stored as it is needs no steps: it is
  ready when opened, and its source is a span of the PDF's own media
  source, so its bytes are never copied.
- A JPEG an encrypted file stores is copied out a piece at a time,
  decrypted as it is read (`PDF-RAW-READ`).
- A JPEG behind other filters is decoded out of them on the first step
  (`PDF-STREAM-IMAGE`).
- Samples under no filter, or under `FlateDecode` alone, are read and
  inflated a piece at a time, each row's predictor undone as it comes
  (the PNG predictors through `PNG-UNFILTER`, the TIFF one for eight-bit
  samples), turned into pixels and encoded (`QOI-ENC-PIXELS`). Neither the
  samples nor the pixels are ever held whole: the inflater's window, which
  the stream's zlib header sizes, two rows and the file being written.
- Samples under other filters are decoded whole on the first step, then
  turned into pixels a row at a time.

A soft mask is read the same way beside its picture, one of its rows for
each the picture needs. Data that runs short or is damaged fails the file
with `PDF-S-DAMAGED`; memory refused, with `PDF-S-MEMORY`. A failed file is
given back at once; `PDF-IMAGE-FREE` gives back the rest, at any step.

`PDF-IMAGE-SOURCE` makes a source for the ready file: a span of the PDF for
a stored JPEG (`MEDSRC-SPAN`), else the file the record holds
(`MEDSRC-MEMORY`). It is valid until `PDF-IMAGE-FREE`. Each picture has its
own record, the QOI encoder's state included, so pictures may take turns;
one call runs at a time. Memory comes from the file's memory source.

## Cost

A picture of 160 by 120 noisy RGB pixels costs about 950 steps a pixel
to turn into QOI when stored without a filter: about 610 for the QOI
encoder and 340 to make the pixels. Under `FlateDecode` it costs about
2,200 a pixel, the rest inflating some 55 KB, about 440 steps a compressed
byte. Opening a stored JPEG costs about 46,000 steps and nothing more.
