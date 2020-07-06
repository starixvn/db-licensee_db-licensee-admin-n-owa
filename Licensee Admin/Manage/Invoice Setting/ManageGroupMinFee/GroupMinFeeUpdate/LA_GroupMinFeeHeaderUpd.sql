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
	@ErrMsg			NVARCHAR(4000)	= ''	OUTPUT
AS
/*  
	 Created: 20200701@Happy
	 Task : Update GroupMinFee
	 DB: DBCUST.bodb_Licensee
	 
	 Revisions:
	 
	 Params's Explanation:
	
*/
BEGIN
	SET NOCOUNT ON;
	
	IF EXISTS (SELECT 1 FROM dbo.LA_GroupMinFeeHeader WITH(NOLOCK) WHERE (Name = @GroupName AND GroupMinFeeID <> @GroupMinFeeID))
	BEGIN
		SELECT @ErrMsg = 'Group name exists please try again.', @ErrCode = 506
		RETURN
	END

	--#Region backup
	SET @OldData = (
		SELECT GroupMinFeeID, Name, FromDate, ToDate
		FROM dbo.LA_GroupMinFeeHeader WITH(NOLOCK)
		WHERE GroupMinFeeID = @GroupMinFeeID FOR XML PATH('GroupMinFeeHeader'), ROOT('Root'))
	--#Endregion
	
	--Region update
	UPDATE dbo.LA_GroupMinFeeHeader WITH(ROWLOCK, UPDLOCK)
	SET Name = @GroupName,
		FromDate = @FromDate,
		ToDate = @ToDate
	WHERE GroupMinFeeID = @GroupMinFeeID
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update LA_GroupMinFeeHeader failed. Please try again.', @ErrCode = 503
		RETURN
	END
	--#Endregion
END
GO
