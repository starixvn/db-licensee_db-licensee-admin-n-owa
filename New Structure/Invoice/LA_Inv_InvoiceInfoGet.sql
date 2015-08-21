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
	DECLARE @InvoiceHeaderId INT = 117
	
	EXEC LA_Inv_InvoiceInfoGet @InvoiceHeaderId
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @BaseCurrencyTable AS TABLE(CurrencyId INT, CurrencyName VARCHAR(5))
	INSERT	INTO @BaseCurrencyTable(CurrencyId,CurrencyName)
	EXECUTE bodb_Licensee.dbo.LA_SelBaseCurrency
	
	SELECT TOP 1	
			i.InvoiceHeaderId,
			i.BillerId,
			i.PartyId,
			i.RefNo,
			i.CurrencyId,
			bct.CurrencyName,
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
			INNER JOIN dbo.LA_InvoiceSetting lis ON i.BillerId = lis.ToPartyId AND i.PartyId = lis.FromPartyId AND i.InvoiceType = lis.InvTypeId
			INNER JOIN dbo.LA_InvoiceTemplate lit ON lis.InvTempId = lit.InvTemplateId
			INNER JOIN @BaseCurrencyTable bct ON i.CurrencyId = bct.CurrencyId
	WHERE	i.InvoiceHeaderId = @InvoiceHeaderId
			AND i.HasDeleted = 0
	
	SELECT	i.InvoiceHeaderId,
			i.[Description],
			i.Reference,
			i.ProductId,
			CASE				
				WHEN i.ProductId = 0 THEN 'SB' 
				ELSE p.ProductPrefix
			END AS ProductCode,
			i.AmountType,
			i.InvoiceAmount
	FROM	dbo.LA_InvoiceDetail i WITH (NOLOCK)
			LEFT JOIN dbo.Product3rd p WITH(NOLOCK) ON i.ProductId = p.Productid	
	WHERE	i.InvoiceHeaderId = @InvoiceHeaderId
END		

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceInfoGet] TO bodbAdminNet