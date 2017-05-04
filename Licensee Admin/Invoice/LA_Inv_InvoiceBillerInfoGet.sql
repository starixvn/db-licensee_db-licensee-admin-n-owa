USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceBillerInfoGet] 
	  @BillerId		INT
	, @PayerId		INT
	, @InvoiceType	INT
	, @Environment	VARCHAR(20)
AS
/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DBLIC/bodb_Licensee

	Revisions: 
		+ 20150806@Bravo: Invoice Biller Info - Get
		+ 20151019@Victor: Support Chinese on Invoice's text fields
		+ 20160728@Bruce: Software data fee & hosting fee have a same invoice no
		+ 20170421@Bruce: Add environment filter
*/
/*	Example:
	USE bodb_licensee
	DECLARE @BillerId INT = 115
	DECLARE @PartyId INT = 17
	DECLARE @InvoiceType INT = 1
	EXEC LA_Inv_InvoiceBillerInfoGet @BillerId, @PartyId, @InvoiceType
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @InvoiceInfo AS TABLE(
		InvoiceSymbol		NVARCHAR(20),
		InvoiceNumber		INT,
		InvoiceTemplateId	SMALLINT,
		InvoiceTemplateName	VARCHAR(50),
		InvoiceTemplatePath	VARCHAR(255),
		IsSeparateProduct	BIT
	)
	INSERT INTO @InvoiceInfo(InvoiceTemplateId,InvoiceTemplateName,InvoiceTemplatePath)
	(
		SELECT	ivs.InvTempId, itpl.InvTemplateName, itpl.TemplatePath
		FROM	dbo.LA_InvoiceSetting ivs WITH(NOLOCK) 
				INNER JOIN dbo.LA_InvoiceTemplate itpl WITH(NOLOCK) ON ivs.InvTempId = itpl.InvTemplateId
		WHERE	ivs.FromPartyId = @PayerId
				AND ivs.ToPartyId = @BillerId
		GROUP	BY ivs.InvTempId, itpl.InvTemplateName, itpl.TemplatePath
	)

	DECLARE @HostingFeeInvoiceType INT = (SELECT InvTypeId FROM LA_InvoiceType WITH(NOLOCK) WHERE InvTypeName = 'Hosting Fees')

	DECLARE @InvoiceTmp TABLE(
			BillerId		INT,
			InvoiceType		INT,
			InvoiceSymbol	NVARCHAR(20),
			InvoiceNumber	INT)
	INSERT	INTO @InvoiceTmp
	SELECT	i.BillerId,
			i.InvoiceType,
			i.InvoiceSymbol,
			MAX(i.InvoiceNumber)
	FROM	LA_InvoiceHeader i WITH(NOLOCK)
	WHERE	i.BillerId = @BillerId AND (i.Environment IS NULL OR i.Environment = @Environment)
	GROUP BY i.BillerId,i.InvoiceType,i.InvoiceSymbol,i.InvoiceDate
	ORDER BY i.InvoiceDate DESC
		
	DECLARE @InvoiceSymbol NVARCHAR(20) = ''
	DECLARE @InvoiceNumber INT = 1

	IF @InvoiceType IN (1, @HostingFeeInvoiceType)
	BEGIN
		SELECT	TOP 1 @InvoiceSymbol = i.InvoiceSymbol
		FROM	@InvoiceTmp i
		WHERE	i.InvoiceType IN (1, @HostingFeeInvoiceType)
	END
	ELSE
	BEGIN
		SELECT	TOP 1 @InvoiceSymbol = i.InvoiceSymbol 
		FROM	@InvoiceTmp i
		WHERE	i.InvoiceType = @InvoiceType
	END

	SELECT	@InvoiceNumber = ISNULL(MAX(i.InvoiceNumber), 0) + 1
	FROM	@InvoiceTmp i
			INNER JOIN @InvoiceTmp rf ON i.InvoiceSymbol = rf.InvoiceSymbol	
	WHERE	i.InvoiceSymbol = @InvoiceSymbol
	
	UPDATE	@InvoiceInfo
	SET		InvoiceSymbol = @InvoiceSymbol,
			InvoiceNumber = @InvoiceNumber
	UPDATE	@InvoiceInfo
	SET		IsSeparateProduct = (SELECT TOP 1 i.IsSeparateProduct
								FROM LA_InvoiceHeader i WITH(NOLOCK)
								WHERE i.BillerId = @BillerId
								ORDER BY i.InvoiceNumber DESC)
	
	SELECT	TOP 1 ii.InvoiceSymbol, ii.InvoiceNumber, ii.InvoiceTemplateId, ii.InvoiceTemplateName, ii.InvoiceTemplatePath, ii.IsSeparateProduct
	FROM	@InvoiceInfo ii

END

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceBillerInfoGet] TO bodbAdminNet
