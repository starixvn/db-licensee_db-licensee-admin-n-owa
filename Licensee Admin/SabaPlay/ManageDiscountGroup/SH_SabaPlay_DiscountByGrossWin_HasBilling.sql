/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="1"></info>*/
CREATE PROCEDURE [dbo].[SH_SabaPlay_DiscountByGrossWin_HasBilling]
	@DiscountGroupId SMALLINT
	,@HasBilling 	 BIT = 0 OUTPUT
AS
/*
	Created: 20250516@Eddie
	DB: DBCUST.bodb_licensee
	Task: SabaPlay - Manage Discount Group for SabaPlay - Check this discount has not belong to any a invoice yet

	Revisions:  
		- 20250516@Eddie: Initialize SP [RedmineID: #220534]

*/
BEGIN
	SET NOCOUNT ON
	DECLARE @FromDate DATETIME
		  , @ToDate DATETIME
		  , @InvoiceType INT = 1

	DECLARE @Operators TABLE (PartyId INT)

	-- Get time range
	SELECT @FromDate = FromDate, @ToDate = ToDate
	FROM dbo.LA_DiscountGroupHeader WITH (NOLOCK)
	WHERE DiscountGroupId = @DiscountGroupId

	-- Get operator list
	INSERT INTO @Operators
	SELECT PartyID
	FROM dbo.LA_DiscountGroupAssignment WITH (NOLOCK) 
	WHERE DiscountGroupId = @DiscountGroupId

	IF(EXISTS(
		SELECT 1
		FROM dbo.LA_InvoiceHeader ih WITH (NOLOCK)
		INNER JOIN @Operators p ON ih.PartyId = p.PartyId 
		WHERE ih.ToDate >= @FromDate AND ih.ToDate <= @ToDate
			  AND ih.InvoiceType = @InvoiceType
			  AND ih.StatusId <> -1 -- void
	))
	BEGIN
		SELECT @HasBilling = 1
	END
	ELSE
	BEGIN
		SELECT @HasBilling = 0
	END

END
GO