# Active Quick Mask in layered TIFF

These files contain maintainer-owned synthetic RGB16 artwork. Photoshop 2026 27.2 wrote both references using Save As TIFF. The first has a Select All Quick Mask, two raster layers and composite opacity. The second entered Quick Mask without a previous selection, retains the Proof ink spot and Alpha 2, and omits composite opacity. Photoshop reopened the second file in Quick Mask mode.

The fixtures retain Photoshop's original lossless raster strips, layer payload, applicable transparency marker and channel metadata. The test copies rebuild the TIFF directory and omit application metadata, thumbnails, profiles and unrelated Photoshop blocks. Resource 1022 is `00 03 00` with composite opacity and `00 05 01` with two saved channels. The physical TIFF opacity sample and its name do not change the Quick Mask index.
