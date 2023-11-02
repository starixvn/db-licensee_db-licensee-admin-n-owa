/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20231026@Danny
	DB: DBCUST.bodb_licensee
	Task: Add new Payment table RedmineId #193656
*/
USE bodb_licensee
GO


CREATE TABLE [dbo].[LA_Payment](
	[PaymentId] [bigint] IDENTITY(1,1) NOT NULL,
	[PaymentNo] [varchar](50) NULL,
	[ReceivedDate] [date] NULL,
	[Type] [tinyint] NULL,
	[PartyID] [int] NULL,
	[CurrencyId] [int] NULL,
	[Amount] [money] NULL,
	[RemainingAmount] [money] NULL,
	[TransferRefno] [bigint] NULL,
	[StatusId] [smallint] NULL,
	[Environment] [varchar](50) NULL,
	[CreatedDate] [datetime] NULL,
	[CreatedBy] [int] NULL,
	[ModifyDate] [datetime] NULL,
	[ModifiedBy] [int] NULL,
	[Remark] [nvarchar](500) NULL,
PRIMARY KEY CLUSTERED 
(
	[PaymentId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [DATA]
) ON [DATA]
GO



