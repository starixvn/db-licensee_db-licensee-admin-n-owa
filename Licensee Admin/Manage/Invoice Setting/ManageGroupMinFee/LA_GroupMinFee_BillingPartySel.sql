/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFee_BillingPartySel]
	@GroupMinFeeId INT
AS
/*  
	 Created: 20200706@Mason [#134492]
	 Task: Select billing party in Group Min Fee
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20200706@Mason: Implement Group Min Fee [#134492]

	 Params:

	 Explannation: EXEC LA_GroupMinFee_BillingPartySel @@GroupMinFeeId = 1
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @GroupFromDate DATETIME, @GroupToDate DATETIME, @InvoiceTypeGroupMinFee INT = 1, @SB_ProductId INT = 0
	DECLARE @PartiesSettings TABLE(PartyId INT, ProductId INT)

	--#Region Get info of Discount 
	-- Get Time range
	SELECT @GroupFromDate = FromDate, @GroupToDate = ToDate
	FROM dbo.LA_GroupMinFeeHeader WITH(NOLOCK)
	WHERE GroupMinFeeID = @GroupMinFeeId
	-- Get Party List
	INSERT INTO @PartiesSettings(PartyId, ProductId)
	SELECT a.PartyID, @SB_ProductId
	FROM dbo.LA_GroupMinFeeHeader h WITH(NOLOCK) 	 
		INNER JOIN dbo.LA_GroupMinFeeAssignment a WITH(NOLOCK) ON h.GroupMinFeeID = a.GroupMinFeeID
	WHERE h.GroupMinFeeID = @GroupMinFeeId 
	--#Endregion Get info of Discount

	SELECT DISTINCT ih.PartyId
	FROM dbo.LA_InvoiceHeader ih WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceStatement id WITH(NOLOCK) ON ih.InvoiceHeaderId = id.InvoiceHeaderId
		INNER JOIN @PartiesSettings p ON ih.PartyId = p.PartyId AND id.ProductId = p.ProductId	
	WHERE ih.ToDate >= @GroupFromDate AND ih.ToDate <= @GroupToDate
			AND ih.InvoiceType = @InvoiceTypeGroupMinFee 
			AND ih.StatusId = 0 -- normal invoice
END
GO