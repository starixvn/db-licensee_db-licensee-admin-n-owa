/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceInfoGet] 
	  @InvoiceHeaderId INT	
AS
/*	Header:
	Created: 2015.08.07 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_Licensee
   
	Revisions: 
		- 20150807@Bravo: Invoice Info - Get
        - 20160805@Bruce: Include hosting fee info
        - 20171220@Parsons: increase length for variables [#88197]
*/
/*	Example:
	USE bodb_licensee
	DECLARE @InvoiceHeaderId INT = 117
	
	EXEC LA_Inv_InvoiceInfoGet @InvoiceHeaderId
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @BaseCurrencyTable AS TABLE(CurrencyId INT, CurrencyName VARCHAR(10))
	INSERT	INTO @BaseCurrencyTable(CurrencyId,CurrencyName)
	EXECUTE CustDB.dbo.LA_BaseCurrency_Sel
	
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
			i.IsSeparateProduct,
			i.MaxPCU,
			i.RateAmount,
			i.IsWaived
	FROM	dbo.LA_InvoiceHeader i WITH(NOLOCK)
			INNER JOIN dbo.LA_InvoiceSetting lis WITH(NOLOCK) ON i.BillerId = lis.ToPartyId AND i.PartyId = lis.FromPartyId AND i.InvoiceType = lis.InvTypeId
			INNER JOIN dbo.LA_InvoiceTemplate lit WITH(NOLOCK) ON lis.InvTempId = lit.InvTemplateId
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