/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoicePathSel]
	@InvoiceId INT
AS
/*	
	Created: 20170330@Bruce
	Task :	Get invoice metadata [#74096]
	DB:		DBCUST.bodb_Licensee

	Revisions:
		- 20170609@Bruce: add filename [#76411]
*/
BEGIN
	SET NOCOUNT ON
	SELECT 
		ISNULL(InvoicePath, '') AS InvoicePath,
		REPLACE(b.BillerName,' ','-') + '-INV-' + (
			InvoiceSymbol + CASE WHEN InvoiceNumber < 100 THEN RIGHT('000' + CAST(InvoiceNumber AS VARCHAR(10)),3) ELSE CAST(InvoiceNumber AS VARCHAR(10)) END
		) + '-for-' + REPLACE(CASE WHEN ISNULL(d.BrandName,'') = '' THEN p.PartyName ELSE d.BrandName END,' ', '-') + '.pdf' AS [Filename]
		--{billerName}-INV-{invoiceNo}-for-{payerdisplayname}.pdf
	FROM dbo.LA_InvoiceHeader i WITH(NOLOCK)
		INNER JOIN dbo.LA_BillerInfo b WITH(NOLOCK) ON b.PartyId = i.BillerId
		INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID = i.PartyId
		INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON d.PartyID = i.PartyId
	WHERE InvoiceHeaderId = @InvoiceId
END		
GO