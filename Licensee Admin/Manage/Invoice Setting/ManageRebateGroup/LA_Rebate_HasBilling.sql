/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Rebate_HasBilling]
	@GroupId INT, 
	@HasBilling BIT = 0 OUTPUT
AS
/*  
	 Created: 20180529@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20180529@Parsons: Check this rebate has not belong to any a invoice yet [#94282]

	 Params:

	 Explannation: 
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @FromDateRebate DATETIME, @ToDateRebate DATETIME, @InvoiceTypeRebate INT = 3, @InvoiceItemTypeRebate INT = 6
	DECLARE @Parties TABLE(PartyId INT)

	--#Region Get info of Rebate 
	-- Get Time range
	SELECT @FromDateRebate = FromDate, @ToDateRebate = ToDate
	FROM LA_DiscountGroupHeader WITH(NOLOCK)
	WHERE DiscountGroupId = @GroupId
	-- Get Party List
	INSERT INTO @Parties
	SELECT PartyID
	FROM LA_DiscountGroupAssignment WITH(NOLOCK) 
	WHERE DiscountGroupId = @GroupId
	--#Endregion Get info of Rebate

	--#Region Check has not belong to any a invoice yet
	IF(EXISTS(
		SELECT TOP 1 ih.PartyId
		FROM LA_InvoiceHeader ih WITH(NOLOCK)
		INNER JOIN LA_InvoiceStatement id WITH(NOLOCK) ON ih.InvoiceHeaderId = id.InvoiceHeaderId
		INNER JOIN @Parties p ON ih.PartyId = p.PartyId 
		WHERE ih.FromDate >= @FromDateRebate AND ih.ToDate <= @ToDateRebate
			  AND ih.InvoiceType = @InvoiceTypeRebate
			  AND id.InvItemTypeId = @InvoiceItemTypeRebate
			  AND ih.StatusId = 0 -- normal invoice
	))
	BEGIN
		SELECT @HasBilling = 1
	END
	ELSE
	BEGIN
		SELECT @HasBilling = 0
	END
	--#Endregion Check has not belong to any a invoice yet
END
GO