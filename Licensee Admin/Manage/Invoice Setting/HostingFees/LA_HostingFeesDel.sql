/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesDel]
	@HostingFeesId	INT,
	@UserID			INT,
	@LoginIP		VARCHAR (50)	= '',
	@ErrCode		INT				= 0		OUTPUT,
	@ErrMsg			NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20160615@Bravo
	 Task : Delete hosting fees settings
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]

	 Params:
		
	 Example:
		EXEC dbo.[LA_HostingFeesDel] 1
*/
BEGIN	
	SET NOCOUNT ON

	-- For writing log
	DECLARE 
		@startRun	DATETIME = GETDATE(),
		@endRun		DATETIME,
		@duration	INT,
		@logData	NVARCHAR(4000)

	IF EXISTS (SELECT 1 FROM dbo.LA_HostingFeesSetting WITH(NOLOCK) WHERE HostingFeesId = @HostingFeesId)
	BEGIN
		SELECT 	@ErrMsg = 'This setting is being used.', @ErrCode = 2	
		RETURN
	END

	SET @logData = CAST((SELECT
			c.BaseCurrencyId	AS '@bc',
			c.[Description]		AS '@ds',
			c.HostingFeesId		AS '@hi',
			c.HostingFeesName	AS '@hn',
			c.HostingFeesTypeId	AS '@ht',
			(
				SELECT dt.* FROM dbo.LA_HostingFeesDetail dt WITH(NOLOCK)
				WHERE dt.HostingFeesId = @HostingFeesId
				FOR XML PATH('item')
			) AS '@dt'
		FROM dbo.LA_HostingFees c WHERE c.HostingFeesId = @HostingFeesId
		FOR XML PATH('z'), ROOT('r')
	) AS NVARCHAR(4000))

	DELETE FROM dbo.LA_HostingFees WHERE HostingFeesId = @HostingFeesId
	DELETE FROM dbo.LA_HostingFeesDetail WHERE HostingFeesId = @HostingFeesId
	
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 

	-- Write Log
	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@LicenseeID	= 0
		,@CurrencyID	= 0
		,@SPName		= 'LA_HostingFeesDel'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= ''
		,@OldData		= @logData
END
GO