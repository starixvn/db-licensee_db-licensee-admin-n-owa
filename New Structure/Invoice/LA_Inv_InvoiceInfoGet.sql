USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceInfoGet] 
	  @InvoiceHeaderId INT	
AS
/*	Header:
	Created: 2015.08.07 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_Licensee
   
	Revisions: 
		+ 2015.08.07: Invoice Info - Get
*/
/*	Example:
	USE bodb_licensee
	DECLARE @InvoiceHeaderId INT = 8
	
	EXEC LA_Inv_InvoiceInfoGet @InvoiceHeaderId
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT	i.InvoiceHeaderId,
			i.BillerId,
			i.PartyId,
			i.RefNo,
			i.CurrencyId,
			i.InvoiceSymbol,
			i.InvoiceNumber,
			i.FromDate,
			i.ToDate,
			i.InvoiceDate,
			i.DueDate,
			i.Amount,
			i.InvoiceType,
			lis.InvTempId AS InvoiceTemplateId,
			lit.InvTemplateName AS InvoiceTemplateName,
			i.StatusId,
			i.Note,
			i.HasSent,
			i.CreatedBy,
			i.CreatedDateTime,
			i.UpdatedDateTime,
			i.IsSeparateProduct
	FROM	dbo.LA_InvoiceHeader i WITH(NOLOCK)
			INNER JOIN dbo.LA_InvoiceSetting lis ON i.BillerId = lis.ToPartyId AND i.PartyId = lis.FromPartyId
			INNER JOIN dbo.LA_InvoiceTemplate lit ON lis.InvTempId = lit.InvTemplateId
	WHERE	i.InvoiceHeaderId = @InvoiceHeaderId
			AND i.HasDeleted = 0
	
	SELECT	i.InvoiceHeaderId,
			i.ItemName,
			i.Reference,
			i.ProductId,
			i.FeeType,
			i.Amount
	FROM	dbo.LA_InvoiceDetail i WITH (NOLOCK)
	WHERE	i.InvoiceHeaderId = @InvoiceHeaderId
END		

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceInfoGet] TO bodbAdminNet