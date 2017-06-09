USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoicePathSel]
	@InvoiceId INT
AS
/*	
	Created: 20170330@Bruce
	Task :	Get invoice metadata [#74096]
	DB:		DBLIC/bodb_Licensee

	Revision:
		+ 20170609@Bruce: add filename [#76411]
*/
BEGIN
	SET NOCOUNT ON
	SELECT 
		ISNULL(InvoicePath, '') AS InvoicePath,
		REPLACE(b.BillerName,' ','-') + '-INV-' + (
			InvoiceSymbol + CASE WHEN InvoiceNumber < 100 THEN RIGHT('000' + CAST(InvoiceNumber AS VARCHAR(10)),3) ELSE CAST(InvoiceNumber AS VARCHAR(10)) END
		) + '-for-' + REPLACE(ISNULL(d.BrandName,p.PartyName),' ', '-') + '.pdf' AS [Filename]
		--{billerName}-INV-{invoiceNo}-for-{payerdisplayname}.pdf
	FROM dbo.LA_InvoiceHeader i WITH(NOLOCK)
		INNER JOIN dbo.LA_BillerInfo b WITH(NOLOCK) ON b.PartyId = i.BillerId
		INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID = i.PartyId
		INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON d.PartyID = i.PartyId
	WHERE InvoiceHeaderId = @InvoiceId
END		

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoicePathSel] TO bodbAdminNet
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Inv_InvoicePathSel] TO vnteam
GO
