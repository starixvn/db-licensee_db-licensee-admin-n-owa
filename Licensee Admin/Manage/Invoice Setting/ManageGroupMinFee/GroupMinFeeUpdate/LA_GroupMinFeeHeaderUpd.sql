/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeHeaderUpd]
	@GroupMinFeeID	SMALLINT,
	@GroupName		NVARCHAR(110),
	@FromDate		DATE,
	@ToDate			DATE,
	@OldData		XML				= ''	OUTPUT,
	@ErrCode		INT				= 0		OUTPUT,
	@ErrMsg			NVARCHAR(4000)	= ''	OUTPUT,
	@Environment			VARCHAR(50)     = 'LOCAL'
AS
/*  
	 Created: 20200701@Happy
	 Task : Update GroupMinFee
	 DB: DBCUST.bodb_Licensee
	 
	 Revisions:
		- 20200701@Happy: Implement Group Min Fee [#134492]
		- 20231108@Danny: return LaunchedDate and the last day of previous billing cycle [#194890]
	 
	 Params's Explanation:
	
*/
BEGIN
	SET NOCOUNT ON;

	DECLARE @MaxInvoiceDate DATE

	SELECT  @MaxInvoiceDate = MAX(InvoiceDate) 
	FROM LA_InvoiceHeader WITH(NOLOCK) 
	WHERE InvoiceType = 1 AND StatusId = 0 AND Environment = @Environment
	
	IF EXISTS (SELECT TOP 1 1 FROM dbo.LA_GroupMinFeeHeader WITH(NOLOCK) WHERE ([Name] = @GroupName AND GroupMinFeeID <> @GroupMinFeeID))
	BEGIN
		SELECT @ErrMsg = 'Group name exists please try again.', @ErrCode = 506
		RETURN
	END

	IF @FromDate <= @MaxInvoiceDate
	BEGIN
		SELECT @ErrMsg = 'Information have changed will affect to current system!', @ErrCode = 507
		RETURN
	END

	--#Region backup
	SET @OldData = (
		SELECT GroupMinFeeID, [Name], FromDate, ToDate
		FROM dbo.LA_GroupMinFeeHeader WITH(NOLOCK)
		WHERE GroupMinFeeID = @GroupMinFeeID FOR XML PATH('GroupMinFeeHeader'), ROOT('Root'))
	--#Endregion backup
	
	--Region update
	UPDATE dbo.LA_GroupMinFeeHeader WITH(ROWLOCK, UPDLOCK)
	SET [Name] = @GroupName,
		FromDate = @FromDate,
		ToDate = @ToDate
	WHERE GroupMinFeeID = @GroupMinFeeID
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update LA_GroupMinFeeHeader failed. Please try again.', @ErrCode = 503
		RETURN
	END
	--#Endregion update
END
GO