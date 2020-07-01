/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeHeaderIns]
	@GroupName			NVARCHAR(110),
	@FromDate			DATE,
	@ToDate				DATE,
	@NewGroupMinFeeId	SMALLINT		= 0		OUTPUT,
	@ErrorCode			INT				= 0		OUTPUT, 
	@ErrorMsg			VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20200630@Happy
	Task : Insert new GroupMinFee
	DB: DBCUST.bodb_Licensee

	Revisions:

	Param's Explannation: 

*/
BEGIN
	SET NOCOUNT ON;
	
	IF EXISTS (SELECT 1 FROM dbo.LA_GroupMinFeeHeader WITH(NOLOCK) WHERE Name = @GroupName)
	BEGIN
		SELECT @ErrorMsg = 'Group name exists please try again.', @ErrorCode = 506
		RETURN
	END
	
	IF (@FromDate >= @ToDate)
	BEGIN
		SELECT @ErrorMsg = 'Cannot save the setting, please check From date/To date.', @ErrorCode = 100
		RETURN
	END
	
	INSERT INTO dbo.LA_GroupMinFeeHeader(Name, FromDate, ToDate)
	VALUES(@GroupName, @FromDate, @ToDate)
	
	SET @NewGroupMinFeeId = SCOPE_IDENTITY()
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrorMsg = 'Insert/Update LA_GroupMinFeeHeader failed. Please try again.', @ErrorCode = 503
		RETURN
	END
END
GO
